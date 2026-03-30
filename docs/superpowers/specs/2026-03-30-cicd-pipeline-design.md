# CI/CD パイプライン設計書

## 概要

Soyoka プロジェクトに GitHub Actions ベースの CI/CD パイプラインを導入する。GitHub Release の公開をトリガーに iOS アプリの App Store Connect アップロードと Backend のデプロイを自動化する。

### 目的

- iOS ビルド・署名・App Store Connect アップロードの完全自動化
- Cloudflare Workers Backend のデプロイ自動化
- リリースノートの自動分類生成
- App Store「What's New」テキストの自動生成

### 技術選定

- **CI/CD**: GitHub Actions（macOS + Linux ランナー）
- **iOS ビルド**: `xcodebuild`（Fastlane 不使用）
- **App Store アップロード**: `xcrun altool` + App Store Connect API Key
- **コード署名**: GitHub Secrets に p12 + Provisioning Profile を Base64 保存
- **Backend デプロイ**: Wrangler CLI

---

## アーキテクチャ

```
GitHub Release 公開 (published)
         │
         ▼
┌─────────────────────────────────────────┐
│  release.yml                            │
│                                         │
│  Job 1: ios-release (macos-15)          │
│    ① 証明書・プロファイル復元            │
│    ② xcodebuild archive                │
│    ③ xcodebuild -exportArchive (IPA)   │
│    ④ xcrun altool --upload-app          │
│    ⑤ IPA を Release アセットに添付      │
│                                         │
│  Job 2: backend-deploy (ubuntu-latest)  │
│    ① npm ci                            │
│    ② npm run typecheck                 │
│    ③ npm run test                      │
│    ④ wrangler deploy --env production  │
│                                         │
│  Job 3: update-whats-new (ubuntu-latest)│
│    ① Release body からテキスト抽出     │
│    ② metadata/ja/release_notes.txt 更新│
│    ③ コミット & プッシュ               │
└─────────────────────────────────────────┘
```

---

## 1. ワークフロー: `release.yml`

### 1.1 トリガー

```yaml
on:
  release:
    types: [published]
```

GitHub の「Create a new release」でリリースを公開した時に発火。draft → publish も対象。

### 1.2 Job 1: `ios-release`（macOS ランナー）

**ランナー**: `macos-15`（Apple Silicon、Xcode 16.4 プリインストール）

**ステップ:**

1. **Checkout**
   - `actions/checkout@v4`

2. **Xcode バージョン選択**
   - `sudo xcode-select -s /Applications/Xcode_16.4.app`

3. **証明書・Provisioning Profile の復元**
   - GitHub Secrets から Base64 デコード
   - 一時 Keychain を作成し p12 をインポート
   - Provisioning Profile を `~/Library/MobileDevice/Provisioning Profiles/` に配置

4. **SPM 依存解決**
   - `xcodebuild -resolvePackageDependencies`

5. **アーカイブ**
   ```bash
   xcodebuild archive \
     -project repository/ios/Soyoka.xcodeproj \
     -scheme Soyoka \
     -archivePath $RUNNER_TEMP/Soyoka.xcarchive \
     -destination 'generic/platform=iOS' \
     CODE_SIGN_STYLE=Manual \
     DEVELOPMENT_TEAM=$TEAM_ID \
     PROVISIONING_PROFILE_SPECIFIER=$PROFILE_NAME
   ```

6. **IPA エクスポート**
   ```bash
   xcodebuild -exportArchive \
     -archivePath $RUNNER_TEMP/Soyoka.xcarchive \
     -exportPath $RUNNER_TEMP/export \
     -exportOptionsPlist repository/ios/ExportOptions.plist
   ```

7. **App Store Connect アップロード**
   ```bash
   xcrun altool --upload-app \
     -f $RUNNER_TEMP/export/Soyoka.ipa \
     -t ios \
     --apiKey $ASC_KEY_ID \
     --apiIssuer $ASC_ISSUER_ID
   ```
   API Key (.p8) は `~/.private_keys/AuthKey_{KEY_ID}.p8` に配置。

8. **IPA を Release アセットに添付**
   - `gh release upload` で IPA ファイルをリリースに添付

9. **Keychain クリーンアップ**
   - 一時 Keychain を削除（`always()` で失敗時も実行）

### 1.3 Job 2: `backend-deploy`（Linux ランナー）

**ランナー**: `ubuntu-latest`

**ステップ:**

1. Checkout
2. Node.js セットアップ（`actions/setup-node@v4`）
3. `npm ci`（依存インストール）
4. `npm run typecheck`（型チェック）
5. `npm run test`（テスト）
6. `npx wrangler deploy --env production`（Cloudflare へデプロイ）

**環境変数**: `CLOUDFLARE_API_TOKEN` を Secrets から注入。

### 1.4 Job 3: `update-whats-new`（Linux ランナー）

**ランナー**: `ubuntu-latest`

**ステップ:**

1. Checkout
2. Release body（リリースノート）を取得
3. 「新機能」「バグ修正」セクションから App Store 用テキストを抽出
4. `metadata/ja/release_notes.txt` に書き出し
5. 変更があればコミット & プッシュ

---

## 2. リリースノート自動分類: `.github/release.yml`

```yaml
changelog:
  exclude:
    labels:
      - "skip-changelog"
  categories:
    - title: "新機能"
      labels:
        - "feat"
    - title: "バグ修正"
      labels:
        - "fix"
    - title: "改善"
      labels:
        - "refactor"
        - "perf"
    - title: "メンテナンス"
      labels:
        - "chore"
        - "ci"
        - "deps"
    - title: "ドキュメント"
      labels:
        - "docs"
    - title: "その他の変更"
      labels:
        - "*"
```

GitHub の「Create a new release」→「Generate release notes」ボタンで自動生成。

---

## 3. ExportOptions.plist

リポジトリにコミットする IPA エクスポート設定:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>upload</string>
</dict>
</plist>
```

配置先: `repository/ios/ExportOptions.plist`

---

## 4. GitHub Secrets

| Secret 名 | 内容 | 用途 |
|:----------|:-----|:-----|
| `CERTIFICATES_P12_BASE64` | 配布証明書（.p12）の Base64 エンコード | iOS コード署名 |
| `CERTIFICATES_P12_PASSWORD` | .p12 のパスワード | Keychain インポート |
| `PROVISIONING_PROFILE_BASE64` | App Store Distribution Profile の Base64 | IPA 署名 |
| `ASC_KEY_ID` | App Store Connect API Key ID | altool 認証 |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID | altool 認証 |
| `ASC_API_KEY_BASE64` | API Key (.p8) の Base64 エンコード | altool 認証 |
| `APPLE_TEAM_ID` | Apple Developer Team ID | ビルド署名 |
| `CLOUDFLARE_API_TOKEN` | Cloudflare Workers API トークン | Backend デプロイ |

---

## 5. コスト見積もり

| ジョブ | ランナー | 所要時間 | 月2回リリース |
|:------|:--------|:--------|:------------|
| ios-release | macOS | ~15分 | 30分 × $0.062 = $1.86 |
| backend-deploy | Linux | ~2分 | 4分 × $0.006 = $0.02 |
| update-whats-new | Linux | ~1分 | 2分 × $0.006 = $0.01 |

**月額: 約 $1.89（GitHub Free プランの無料枠 2,000分以内なら $0）**

macOS 15分 × 10倍 = 150分消費。月2回で300分。Free プランの2,000分枠に十分収まる。

---

## 6. 変更対象ファイル

| ファイル | 種別 | 内容 |
|:--------|:-----|:----|
| `.github/workflows/release.yml` | 新規 | リリースワークフロー |
| `.github/release.yml` | 新規 | リリースノート分類設定 |
| `repository/ios/ExportOptions.plist` | 新規 | IPA エクスポート設定 |

---

## 7. セットアップ手順（手動作業）

以下は GitHub Actions の YAML では自動化できない、人間が行う初期セットアップ:

1. **Apple Developer で配布証明書を作成**
   - Keychain Access → 証明書アシスタント → 証明機関に証明書を要求
   - Apple Developer Portal → Certificates → Distribution 証明書を作成
   - .p12 でエクスポート

2. **Provisioning Profile を作成**
   - Apple Developer Portal → Profiles → App Store Distribution Profile を作成
   - Soyoka の Bundle ID を選択
   - 作成した配布証明書を選択

3. **App Store Connect API Key を作成**
   - App Store Connect → ユーザとアクセス → 統合 → キー
   - 「App Manager」以上の権限でキーを作成
   - .p8 ファイルをダウンロード（1回のみ）

4. **GitHub Secrets に登録**
   ```bash
   # p12 を Base64 エンコード
   base64 -i Certificates.p12 | pbcopy

   # Provisioning Profile を Base64 エンコード
   base64 -i Soyoka_AppStore.mobileprovision | pbcopy

   # API Key を Base64 エンコード
   base64 -i AuthKey_XXXXXXXX.p8 | pbcopy
   ```
   GitHub → Settings → Secrets and variables → Actions → New repository secret

5. **Cloudflare API トークンを取得**
   - Cloudflare ダッシュボード → API Tokens → Create Token
   - 「Edit Cloudflare Workers」テンプレートを使用

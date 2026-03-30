# Apple Developer / CI/CD セットアップ手順書

Soyoka プロジェクトにおける Apple Developer 証明書・プロビジョニングプロファイル・CI/CD 環境の構築手順を記録する。
将来の自分または引き継ぎ者が同じ環境を再現できるレベルの詳細さで記述する。

---

## 1. Apple Developer 証明書の作成

### 1-1. CSR（証明書署名要求）ファイルの作成

1. **Keychain Access** を開く
2. メニューバー → 「Keychain Access」→「証明書アシスタント」→「証明機関に証明書を要求...」
3. 以下を入力する:
   - ユーザのメールアドレス: `soyokaapp@gmail.com`
   - 通称: `SoyokaApp`
   - CA のメールアドレス: 空欄のまま
   - 要求の処理: **「ディスクに保存」** を選択
4. 「続ける」→ デスクトップに `.certSigningRequest` ファイルが保存される

### 1-2. Apple Developer Portal で証明書を発行

1. [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list) を開く
2. **Certificates** → 「+」ボタン
3. 「Apple Distribution」を選択 → 「Continue」
4. CSR ファイル（手順 1-1 で保存したもの）をアップロード → 「Continue」
5. `.cer` ファイルをダウンロードする

### 1-3. Keychain に証明書を追加

1. ダウンロードした `.cer` ファイルをダブルクリックする
2. Keychain Access の「ログイン」キーチェーンに自動追加される

### 1-4. .p12 ファイルとして書き出す

1. **Keychain Access** → 「ログイン」→「自分の証明書」タブ を開く
2. 「Apple Distribution: Yosuke Itomura (BUX437B476)」の ▶ を展開する
3. 証明書（秘密鍵を含む項目）を右クリック → 「書き出す...」
4. フォーマット: **個人情報交換（.p12）**
5. 任意のパスワードを設定して保存する（このパスワードは後で GitHub Secrets に登録）

> **有効期限**: 2027年3月30日

---

## 2. App ID の登録

1. [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list) を開く
2. **Identifiers** → 「+」ボタン
3. Type: **App IDs** → Platform: **iOS** → 「Continue」
4. Bundle ID: **`app.soyoka.ios`**（Explicit）
   - Description: `Soyoka`
   - Capabilities: デフォルトのまま
5. 「Register」

> **注意**: `app.soyoka` は他のデベロッパーに取得済みのため、暫定的に `.ios` サフィックスを付加。
> 正式な Bundle ID `app.soyoka` は Apple Developer Support に問い合わせて取り戻し可能。
> - 問い合わせ先: https://developer.apple.com/contact/
> - 電話が最速（即日〜数日で対応）
> - ドメイン `soyoka.app` の所有証明（Cloudflare DNS 管理画面のスクリーンショット等）が必要

---

## 3. Provisioning Profile の作成

1. [Apple Developer Portal](https://developer.apple.com/account/resources/profiles/list) を開く
2. **Profiles** → 「+」ボタン
3. Distribution → **「App Store Connect」** を選択 → 「Continue」
4. App ID: **`Soyoka (app.soyoka.ios)`** を選択 → 「Continue」
5. Certificate: **`Apple Distribution: Yosuke Itomura`** を選択 → 「Continue」
6. Provisioning Profile Name: `Soyoka AppStore`
7. 「Generate」→ **`.mobileprovision`** ファイルをダウンロードする

---

## 4. App Store Connect API Key の作成

1. [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) を開く
2. **ユーザとアクセス** → **統合** → **App Store Connect API**
3. 「チームキー」タブ → 「+」ボタン
4. 以下を入力:
   - 名前: `GitHub Actions CI`
   - アクセス: **`App Manager`**
5. 「生成」→ **`.p8`** ファイルをダウンロードする

> **重要**: `.p8` ファイルはこの画面を閉じると再ダウンロード不可。必ず安全な場所に保存すること。

6. 以下の値をメモしておく:
   - **Key ID**: キー一覧の「キー ID」列に表示される値
   - **Issuer ID**: 画面上部に表示される UUID

---

## 5. Cloudflare API トークンの作成

1. [Cloudflare ダッシュボード](https://dash.cloudflare.com/profile/api-tokens) を開く
2. **アカウントの管理** → **アカウント API トークン**
3. 「トークンを作成する」をクリック
4. 「**Cloudflare Workers を編集する**」テンプレート → 「テンプレートを使用する」
5. 権限はデフォルトのまま → 「概要に進む」→「トークンを作成」
6. トークンをコピーして保存する

> **重要**: トークンは作成直後の1回のみ表示される。必ず即座にコピーすること。

---

## 6. GitHub Secrets の登録

GitHub → リポジトリ **Settings** → **Secrets and variables** → **Actions** → 「New repository secret」で以下を登録する。

| Secret 名 | 値の取得方法 |
|:----------|:------------|
| `CERTIFICATES_P12_BASE64` | `base64 -i 証明書.p12 \| pbcopy` |
| `CERTIFICATES_P12_PASSWORD` | p12 書き出し時に設定したパスワード |
| `PROVISIONING_PROFILE_BASE64` | `base64 -i Soyoka_AppStore.mobileprovision \| pbcopy` |
| `ASC_KEY_ID` | App Store Connect API Key の Key ID |
| `ASC_ISSUER_ID` | App Store Connect の Issuer ID |
| `ASC_API_KEY_BASE64` | `base64 -i AuthKey_XXXXXXXX.p8 \| pbcopy` |
| `APPLE_TEAM_ID` | `BUX437B476` |
| `CLOUDFLARE_API_TOKEN` | Cloudflare で作成したトークン |

### base64 エンコードの実行例

```bash
# p12 証明書
base64 -i ~/Desktop/SoyokaApp.p12 | pbcopy

# Provisioning Profile
base64 -i ~/Downloads/Soyoka_AppStore.mobileprovision | pbcopy

# App Store Connect API Key
base64 -i ~/Downloads/AuthKey_XXXXXXXX.p8 | pbcopy
```

---

## 7. TelemetryDeck の設定

### アプリの作成

TelemetryDeck ダッシュボードで以下の2つのアプリを作成:

| 用途 | アプリ名 | App ID |
|:-----|:--------|:-------|
| 開発/ステージング | `soyokaApp-dev` | `0D62D235-992D-4FCC-9B99-22C717F94AA2` |
| 本番 | `soyokaApp` | `AEB9BDE7-7494-4C4F-A281-A6485D8CFE97` |

### iOS コードでの環境分離

`SoyokaApp.swift` で DEBUG / Release を切り替える:

```swift
#if DEBUG
// 開発用: dev App ID + テストモード有効
TelemetryDeck.initialize(config: .init(appID: "0D62D235-992D-4FCC-9B99-22C717F94AA2", testMode: true))
#else
// 本番用: 本番 App ID
TelemetryDeck.initialize(config: .init(appID: "AEB9BDE7-7494-4C4F-A281-A6485D8CFE97"))
#endif
```

---

## 8. Bundle ID の変更

### 変更内容

Xcode プロジェクト (`repository/ios/Soyoka.xcodeproj/project.pbxproj`) で以下を変更:

| 変更前 | 変更後 |
|:------|:------|
| `app.soyoka` | `app.soyoka.ios` |
| `app.soyoka.SoyokaTests` | `app.soyoka.ios.SoyokaTests` |

### 変更の経緯

- `app.soyoka` は他のデベロッパーが先に取得済みであることが判明
- Apple Developer Portal でそのまま登録しようとするとエラーが発生
- 暫定措置として `app.soyoka.ios` を使用する
- 正式な `app.soyoka` の取り戻しは Apple Developer Support に問い合わせ予定

**対応コミット**: `bcd137c`

---

## 9. CI/CD ワークフロー

以下のファイルがリポジトリに配置済み:

### `.github/workflows/release.yml`

GitHub Release 公開時に自動発火するワークフロー。以下の3ジョブで構成:

| Job | 実行内容 | ランナー |
|:----|:--------|:--------|
| Job 1 | iOS ビルド → IPA 生成 → App Store Connect アップロード | macOS |
| Job 2 | Backend デプロイ（Cloudflare Workers） | ubuntu-latest |
| Job 3 | What's New テキスト自動生成 | ubuntu-latest |

### `.github/release.yml`

GitHub のリリースノート自動生成設定。PR ラベルによる変更分類。

### `repository/ios/ExportOptions.plist`

IPA エクスポート設定ファイル。`method: app-store` を指定。

---

## 10. 関連ドキュメント

| ドキュメント | パス |
|:-----------|:----|
| CI/CD パイプライン設計書 | `docs/superpowers/specs/2026-03-30-cicd-pipeline-design.md` |
| CI/CD 実装計画 | `docs/superpowers/plans/2026-03-30-cicd-pipeline.md` |
| 強制アップデート運用手順 | `repository/backend/docs/force-update-operations.md` |

---

## 備考・プロジェクト情報

| 項目 | 値 |
|:----|:--|
| Apple Developer Team ID | `BUX437B476` |
| Apple Developer アカウント | Yosuke Itomura |
| GitHub リポジトリ | `git@github.com:yoskmr/VoiceMemo.git` |
| Bundle ID（現在） | `app.soyoka.ios` |
| Bundle ID（正式・取り戻し予定） | `app.soyoka` |
| 証明書有効期限 | 2027年3月30日 |
| Developer Email | `soyokaapp@gmail.com` |

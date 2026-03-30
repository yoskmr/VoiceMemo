# CI/CD パイプライン 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Release 公開をトリガーに iOS ビルド→App Store アップロード、Backend デプロイ、What's New 生成を自動化する。

**Architecture:** GitHub Actions の 3 ジョブ構成。`ios-release`（macOS）で xcodebuild archive → altool アップロード、`backend-deploy`（Linux）で Wrangler デプロイ、`update-whats-new`（Linux）で Release body から App Store テキスト生成。

**Tech Stack:** GitHub Actions, xcodebuild, xcrun altool, Wrangler CLI, gh CLI

**Spec:** `docs/superpowers/specs/2026-03-30-cicd-pipeline-design.md`

---

## ファイル構成

| ファイル | 種別 | 責務 |
|:--------|:-----|:----|
| `.github/release.yml` | 新規 | リリースノート PR ラベル分類 |
| `repository/ios/ExportOptions.plist` | 新規 | IPA エクスポート設定（app-store-connect） |
| `.github/workflows/release.yml` | 新規 | メインワークフロー（3ジョブ） |

---

## Task 1: リリースノート分類設定

**Files:**
- Create: `.github/release.yml`

- [ ] **Step 1: `.github/release.yml` を作成**

```yaml
# .github/release.yml
# GitHub の「Create a new release」→「Generate release notes」で使用される
# PR ラベルに応じてリリースノートをカテゴリ分けする

changelog:
  exclude:
    labels:
      - "skip-changelog"
  categories:
    - title: "🆕 新機能"
      labels:
        - "feat"
    - title: "🐛 バグ修正"
      labels:
        - "fix"
    - title: "🔧 改善"
      labels:
        - "refactor"
        - "perf"
    - title: "🏗️ メンテナンス"
      labels:
        - "chore"
        - "ci"
        - "deps"
    - title: "📝 ドキュメント"
      labels:
        - "docs"
    - title: "その他の変更"
      labels:
        - "*"
```

- [ ] **Step 2: コミット**

```bash
git add .github/release.yml
git commit -m "ci: リリースノート自動分類設定を追加

- PR ラベル（feat/fix/refactor 等）に応じたカテゴリ分け
- GitHub Release の Generate release notes ボタンで自動適用"
```

---

## Task 2: ExportOptions.plist

**Files:**
- Create: `repository/ios/ExportOptions.plist`

- [ ] **Step 1: `ExportOptions.plist` を作成**

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

- [ ] **Step 2: コミット**

```bash
git add repository/ios/ExportOptions.plist
git commit -m "ci(ios): ExportOptions.plist を追加

- App Store Connect 向け IPA エクスポート設定
- dSYM シンボルアップロード有効"
```

---

## Task 3: リリースワークフロー

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: `.github/workflows/release.yml` を作成**

```yaml
# .github/workflows/release.yml
name: Release

on:
  release:
    types: [published]

# 同時実行制御: リリースワークフローは1つだけ実行
concurrency:
  group: release
  cancel-in-progress: false

jobs:
  # ==============================
  # Job 1: iOS ビルド → App Store Connect アップロード
  # ==============================
  ios-release:
    name: iOS Release
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.4.app/Contents/Developer

      # --- 証明書・Provisioning Profile の復元 ---
      - name: Install certificates and provisioning profile
        env:
          CERTIFICATES_P12_BASE64: ${{ secrets.CERTIFICATES_P12_BASE64 }}
          CERTIFICATES_P12_PASSWORD: ${{ secrets.CERTIFICATES_P12_PASSWORD }}
          PROVISIONING_PROFILE_BASE64: ${{ secrets.PROVISIONING_PROFILE_BASE64 }}
        run: |
          # 一時 Keychain を作成
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # p12 証明書をインポート
          CERT_PATH=$RUNNER_TEMP/certificate.p12
          echo -n "$CERTIFICATES_P12_BASE64" | base64 --decode -o "$CERT_PATH"
          security import "$CERT_PATH" \
            -P "$CERTIFICATES_P12_PASSWORD" \
            -A \
            -t cert \
            -f pkcs12 \
            -k "$KEYCHAIN_PATH"
          security set-key-partition-list \
            -S apple-tool:,apple: \
            -k "$KEYCHAIN_PASSWORD" \
            "$KEYCHAIN_PATH"
          security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

          # Provisioning Profile を配置
          PP_PATH=$RUNNER_TEMP/profile.mobileprovision
          echo -n "$PROVISIONING_PROFILE_BASE64" | base64 --decode -o "$PP_PATH"

          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          PP_UUID=$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< $(/usr/bin/security cms -D -i "$PP_PATH"))
          cp "$PP_PATH" ~/Library/MobileDevice/Provisioning\ Profiles/"$PP_UUID".mobileprovision

      # --- App Store Connect API Key の配置 ---
      - name: Install App Store Connect API Key
        env:
          ASC_API_KEY_BASE64: ${{ secrets.ASC_API_KEY_BASE64 }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
        run: |
          mkdir -p ~/.private_keys
          echo -n "$ASC_API_KEY_BASE64" | base64 --decode -o ~/.private_keys/AuthKey_${ASC_KEY_ID}.p8

      # --- ビルド ---
      - name: Resolve SPM dependencies
        run: |
          xcodebuild -resolvePackageDependencies \
            -project repository/ios/Soyoka.xcodeproj \
            -scheme Soyoka

      - name: Archive
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          xcodebuild archive \
            -project repository/ios/Soyoka.xcodeproj \
            -scheme Soyoka \
            -archivePath $RUNNER_TEMP/Soyoka.xcarchive \
            -destination 'generic/platform=iOS' \
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
            | xcbeautify || true

      - name: Export IPA
        run: |
          xcodebuild -exportArchive \
            -archivePath $RUNNER_TEMP/Soyoka.xcarchive \
            -exportPath $RUNNER_TEMP/export \
            -exportOptionsPlist repository/ios/ExportOptions.plist

      # --- アップロード ---
      - name: Upload to App Store Connect
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: |
          xcrun altool --upload-app \
            -f $RUNNER_TEMP/export/Soyoka.ipa \
            -t ios \
            --apiKey "$ASC_KEY_ID" \
            --apiIssuer "$ASC_ISSUER_ID"

      - name: Upload IPA to Release assets
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release upload "${{ github.event.release.tag_name }}" \
            $RUNNER_TEMP/export/Soyoka.ipa \
            --clobber

      # --- クリーンアップ ---
      - name: Clean up keychain
        if: always()
        run: |
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          if [ -f "$KEYCHAIN_PATH" ]; then
            security delete-keychain "$KEYCHAIN_PATH"
          fi
          rm -f $RUNNER_TEMP/certificate.p12
          rm -f $RUNNER_TEMP/profile.mobileprovision
          rm -rf ~/.private_keys

  # ==============================
  # Job 2: Backend デプロイ
  # ==============================
  backend-deploy:
    name: Backend Deploy
    runs-on: ubuntu-latest
    timeout-minutes: 10
    defaults:
      run:
        working-directory: repository/backend
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
          cache-dependency-path: repository/backend/package-lock.json

      - name: Install dependencies
        run: npm ci

      - name: Type check
        run: npm run typecheck

      - name: Run tests
        run: npm run test

      - name: Deploy to Cloudflare Workers
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
        run: npx wrangler deploy --env production

  # ==============================
  # Job 3: What's New テキスト生成
  # ==============================
  update-whats-new:
    name: Update What's New
    runs-on: ubuntu-latest
    timeout-minutes: 5
    needs: [ios-release]
    permissions:
      contents: write
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.release.target_commitish }}
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract What's New from release body
        env:
          RELEASE_BODY: ${{ github.event.release.body }}
          RELEASE_TAG: ${{ github.event.release.tag_name }}
        run: |
          mkdir -p metadata/ja

          # Release body をそのまま What's New テキストとして使用
          # （4000文字制限に注意）
          echo "$RELEASE_BODY" \
            | sed 's/^## //g' \
            | sed 's/^### //g' \
            | sed '/^$/d' \
            | head -c 4000 \
            > metadata/ja/release_notes.txt

          echo "--- Generated What's New for $RELEASE_TAG ---"
          cat metadata/ja/release_notes.txt

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

          if git diff --quiet metadata/ja/release_notes.txt 2>/dev/null; then
            echo "No changes to commit"
          else
            git add metadata/ja/release_notes.txt
            git commit -m "chore: What's New テキストを ${{ github.event.release.tag_name }} で更新"
            git push
          fi
```

- [ ] **Step 2: YAML の構文チェック**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

- [ ] **Step 3: コミット**

```bash
git add .github/workflows/release.yml
git commit -m "ci: GitHub Actions リリースワークフローを追加

- iOS: xcodebuild archive → altool で App Store Connect アップロード
- Backend: typecheck + test → wrangler deploy --env production
- What's New: Release body から App Store 用テキスト自動生成
- GitHub Release 公開時に自動発火（release: published）"
```

---

## Task 4: 初回リリーステスト用の確認

- [ ] **Step 1: ワークフローの存在確認**

```bash
ls -la .github/workflows/release.yml .github/release.yml repository/ios/ExportOptions.plist
```

Expected: 3ファイルとも存在

- [ ] **Step 2: GitHub Secrets の設定状況を確認**

以下の Secrets が GitHub リポジトリに登録済みか確認（手動作業）:

```
CERTIFICATES_P12_BASE64
CERTIFICATES_P12_PASSWORD
PROVISIONING_PROFILE_BASE64
ASC_KEY_ID
ASC_ISSUER_ID
ASC_API_KEY_BASE64
APPLE_TEAM_ID
CLOUDFLARE_API_TOKEN
```

確認コマンド（gh CLI）:

```bash
gh secret list
```

**注意**: Secrets が未登録の場合、設計書セクション7「セットアップ手順（手動作業）」に従って登録する。

- [ ] **Step 3: プッシュ**

```bash
git push origin development
```

ワークフローが `.github/workflows/` に push されれば GitHub Actions に認識される。
実際のリリースフローは GitHub Release を作成した時に初めて発火する。

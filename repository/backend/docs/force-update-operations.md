# 強制アップデート 運用ドキュメント

## 1. 概要

Cloudflare KV に保存した `minimum_app_version` と `app_store_url` をバックエンド API が返すことで、古いバージョンの iOS アプリを起動時にブロックし、App Store へ誘導する仕組み。

---

## 2. アーキテクチャ

```
Cloudflare KV
  ├── minimum_app_version  (例: "1.1.0")
  └── app_store_url        (例: "https://apps.apple.com/jp/app/soyoka/idXXXXXXXXXX")
         │
         ▼
  Backend API  GET /v1/app-version
         │  JSON レスポンス:
         │  {
         │    "minimumVersion": "1.1.0",
         │    "appStoreUrl": "https://..."
         │  }
         │
         ▼
  iOS アプリ (Soyoka)
    - 起動時 / フォアグラウンド復帰時（5分間隔）に API を呼び出す
    - 現在のアプリバージョン < minimumVersion の場合、強制アップデートダイアログを表示
    - ユーザーは appStoreUrl へ遷移するか、アプリを閉じるしか操作できない
```

---

## 3. KV キー一覧

| キー名 | 型 | 説明 | 例 |
|:---|:---|:---|:---|
| `minimum_app_version` | string (semver) | この値未満のアプリをブロックする最低バージョン | `1.1.0` |
| `app_store_url` | string (URL) | 強制アップデートダイアログから遷移する App Store の直リンク | `https://apps.apple.com/jp/app/soyoka/idXXXXXXXXXX` |

> **注意**: `minimum_app_version` は必ず `X.Y.Z` 形式（semver）で設定すること。形式が不正な場合は API が 500 エラーを返す。

---

## 4. 発動手順

強制アップデートを発動させるには、`minimum_app_version` を現行リリースバージョンより大きい値に設定する。

### dev 環境

```bash
# minimum_app_version を設定
wrangler kv key put "minimum_app_version" "1.1.0" --env dev --binding KV

# app_store_url を設定（未設定の場合は強制アップデートが発動しないため必須）
wrangler kv key put "app_store_url" "https://apps.apple.com/jp/app/soyoka/idXXXXXXXXXX" --env dev --binding KV
```

### staging 環境

```bash
wrangler kv key put "minimum_app_version" "1.1.0" --env staging --binding KV
wrangler kv key put "app_store_url" "https://apps.apple.com/jp/app/soyoka/idXXXXXXXXXX" --env staging --binding KV
```

### production 環境（将来対応）

```bash
# 現時点では未構築。将来 https://api.soyoka.app で稼働予定
wrangler kv key put "minimum_app_version" "1.1.0" --env production --binding KV
wrangler kv key put "app_store_url" "https://apps.apple.com/jp/app/soyoka/idXXXXXXXXXX" --env production --binding KV
```

---

## 5. 解除手順

`minimum_app_version` を現行リリースバージョン以下の値（通常は `1.0.0`）に戻すことで強制アップデートを解除できる。

### dev 環境

```bash
wrangler kv key put "minimum_app_version" "1.0.0" --env dev --binding KV
```

### staging 環境

```bash
wrangler kv key put "minimum_app_version" "1.0.0" --env staging --binding KV
```

### production 環境（将来対応）

```bash
wrangler kv key put "minimum_app_version" "1.0.0" --env production --binding KV
```

---

## 6. 確認方法

curl でエンドポイントを叩き、現在の KV 設定値を確認する。

### dev 環境

```bash
curl -s https://api-dev.soyoka.app/v1/app-version | jq .
```

### staging 環境

```bash
curl -s https://api-staging.soyoka.app/v1/app-version | jq .
```

### production 環境（将来対応）

```bash
curl -s https://api.soyoka.app/v1/app-version | jq .
```

**期待するレスポンス例:**

```json
{
  "minimumVersion": "1.1.0",
  "appStoreUrl": "https://apps.apple.com/jp/app/soyoka/idXXXXXXXXXX"
}
```

---

## 7. 注意事項

| 項目 | 内容 |
|:---|:---|
| semver 形式 | `minimum_app_version` は必ず `X.Y.Z` 形式で設定すること。`1.1`、`v1.1.0` などの不正形式は API が 500 エラーを返す |
| `app_store_url` が空の場合 | バージョンが古くても強制アップデートは発動しない。発動させるには両方の KV キーが設定されている必要がある |
| KV 更新の即時反映 | KV の値は更新後即時反映される。デプロイは不要 |
| iOS アプリのチェックタイミング | 起動時、およびフォアグラウンド復帰時（前回チェックから 5 分以上経過した場合）に API を呼び出す |
| ネットワークエラー時の挙動 | API が応答しない・タイムアウトした場合はブロックせず、アプリは通常通り動作する（ユーザーを不当にブロックしない設計） |

---

## 8. トラブルシューティング

### 設定したのに強制アップデートが発動しない

1. `app_store_url` が空になっていないか確認する

   ```bash
   curl -s https://api-dev.soyoka.app/v1/app-version | jq '.appStoreUrl'
   ```

   空文字または `null` の場合、`app_store_url` を設定し直す。

2. `minimum_app_version` が正しい semver 形式か確認する

   ```bash
   curl -s https://api-dev.soyoka.app/v1/app-version | jq '.minimumVersion'
   ```

   `null` や 500 エラーが返る場合は、`X.Y.Z` 形式で再設定する。

3. iOS アプリのバージョンが `minimum_app_version` を下回っているか確認する（設定値以上のバージョンでは発動しない）。

### 全ユーザーがブロックされてしまった

`minimum_app_version` を現行の最新リリースバージョン以下（通常 `1.0.0`）に戻す。KV 更新は即時反映されるため、デプロイ不要。

```bash
# dev
wrangler kv key put "minimum_app_version" "1.0.0" --env dev --binding KV

# staging
wrangler kv key put "minimum_app_version" "1.0.0" --env staging --binding KV

# production（将来対応）
wrangler kv key put "minimum_app_version" "1.0.0" --env production --binding KV
```

### wrangler コマンドが失敗する

- `wrangler` がインストールされているか確認: `npx wrangler --version`
- Cloudflare アカウントへのログイン状態を確認: `npx wrangler whoami`
- KV namespace の binding 名が `wrangler.toml` の設定と一致しているか確認

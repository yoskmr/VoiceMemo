# Phase 3a: Backend Proxy MVP 設計書

## 概要

Soyoka の Backend Proxy を Cloudflare Workers 上に MVP スコープで構築する。iOSアプリからの AI 処理リクエストを受け、GPT-4o mini に中継し、結果を返却する。

## スコープ

### 含む（MVP）

| 機能 | 関連要件 | 説明 |
|:-----|:---------|:-----|
| Cloudflare Workers + Hono 初期構築 | — | プロジェクト骨格、dev + staging 環境 |
| デバイストークン認証 | NFR-010 | UUID ベースの簡易認証。JWT 発行 |
| AI 処理エンドポイント | REQ-003, 004, 005, 010 | GPT-4o mini 呼び出し（要約+タグ+感情分析） |
| 月次使用量制限 | REQ-011 | KV Store で月15回制限を強制 |
| 使用量確認エンドポイント | REQ-011 | 残り回数を返却 |
| レート制限 | REQ-012 | Cloudflare WAF + Workers middleware |
| dev + staging 環境 | — | wrangler.toml で環境分離 |

### 含まない（Phase 3b/3c で対応）

| 機能 | 理由 |
|:-----|:-----|
| Sign In with Apple | Phase 3c で課金と同時対応 |
| App Attest | Phase 3c で認証強化として対応 |
| クラウド高精度 STT | Pro 限定機能。課金実装後に対応 |
| StoreKit 課金検証 / Webhook | Phase 3c の主要スコープ |

## アーキテクチャ

```
iOS App
  ↓ HTTPS TLS 1.3
Cloudflare Edge Network
  ├── WAF + Rate Limiting
  └── Cloudflare Workers (Hono)
        ├── POST /api/v1/auth/device      → デバイストークン発行（JWT）
        ├── POST /api/v1/ai/process       → GPT-4o mini 呼び出し
        ├── GET  /api/v1/usage            → 月次使用量確認
        └── Middleware: JWT検証 + レート制限
             ├── D1 Database（デバイス情報）
             ├── KV Store（月次使用量カウント）
             └── OpenAI API（GPT-4o mini）
```

## ディレクトリ構成

```
repository/backend/
├── package.json                 # 依存: hono, @hono/zod-validator, jose, vitest
├── tsconfig.json
├── wrangler.toml                # dev / staging 環境定義
├── src/
│   ├── index.ts                 # Hono アプリエントリポイント + ルート定義
│   ├── routes/
│   │   ├── auth.ts              # POST /api/v1/auth/device
│   │   ├── ai.ts                # POST /api/v1/ai/process
│   │   └── usage.ts             # GET /api/v1/usage
│   ├── middleware/
│   │   ├── auth.ts              # JWT 検証ミドルウェア
│   │   ├── rateLimit.ts         # レート制限ミドルウェア
│   │   └── requestId.ts         # X-Request-ID 検証・生成
│   ├── services/
│   │   ├── openai.ts            # OpenAI API クライアント（GPT-4o mini）
│   │   ├── quota.ts             # 月次使用量管理（KV Store）
│   │   └── token.ts             # JWT 生成・検証（jose）
│   ├── prompts/
│   │   └── integrated.ts        # 統合プロンプトテンプレート（要約+タグ+感情分析）
│   ├── types.ts                 # 共有型定義（リクエスト/レスポンス）
│   └── errors.ts                # エラーコード定義
├── test/
│   ├── routes/
│   │   ├── auth.test.ts
│   │   ├── ai.test.ts
│   │   └── usage.test.ts
│   ├── middleware/
│   │   ├── auth.test.ts
│   │   └── rateLimit.test.ts
│   ├── services/
│   │   ├── openai.test.ts
│   │   ├── quota.test.ts
│   │   └── token.test.ts
│   └── helpers/
│       └── testUtils.ts         # テストユーティリティ（モックD1/KV等）
├── migrations/
│   └── 0001_initial.sql         # D1 スキーマ（devices テーブル）
├── .dev.vars                    # ローカル開発用シークレット（.gitignore対象）
└── .dev.vars.example            # シークレットのテンプレート
```

## API 詳細設計

### POST /api/v1/auth/device — デバイストークン認証

**目的**: iOS アプリのデバイスを登録し、JWT を発行する。

**リクエスト**:
```json
{
  "device_id": "UUID（iOS の identifierForVendor）",
  "app_version": "1.0.0",
  "os_version": "18.0"
}
```

**レスポンス (200 OK)**:
```json
{
  "access_token": "JWT（有効期限24h）",
  "expires_at": "2026-03-28T01:00:00Z",
  "device_id": "UUID"
}
```

**処理フロー**:
1. device_id のバリデーション（UUIDv4 形式）
2. D1 に devices テーブルで upsert（新規登録 or 最終アクセス更新）
3. JWT 生成（sub: device_id, exp: 24h, iss: soyoka-api）
4. レスポンス返却

**D1 スキーマ**:
```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,           -- device_id (UUID)
  plan TEXT NOT NULL DEFAULT 'free',  -- 'free' | 'pro'
  app_version TEXT,
  os_version TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### POST /api/v1/ai/process — 統合AI処理

設計書 `03-backend-proxy.md` セクション 3.4.1 準拠。

**リクエスト**: テキスト + オプション（要約/タグ/感情分析）
**レスポンス**: 要約 + タグ + 感情分析結果 + usage 情報

**処理フロー**:
1. JWT 検証（middleware/auth.ts）
2. レート制限チェック（middleware/rateLimit.ts）
3. D1 からデバイス情報取得（plan 判定）
4. 無料プランの場合: KV で月次使用量チェック
5. 上限到達: `429 USAGE_LIMIT_EXCEEDED` 返却
6. OpenAI API 呼び出し（統合プロンプト）
7. レスポンスパース・バリデーション
8. KV で使用量カウントインクリメント
9. レスポンス返却
10. テキストデータはメモリから破棄（永続化しない）

**統合プロンプト**: 1回の API 呼び出しで要約・タグ・感情分析を同時実行。JSON 形式で出力を指定。

**月次使用量カウント**: 要約+タグ+感情分析の統合処理を **1回** としてカウント（REQ-011）。

### GET /api/v1/usage — 使用量確認

**レスポンス (200 OK)**:
```json
{
  "used": 3,
  "limit": 15,
  "plan": "free",
  "resets_at": "2026-04-01T00:00:00Z"
}
```

**処理フロー**:
1. JWT 検証
2. KV から `quota:{deviceId}:{YYYY-MM}` を取得
3. D1 からプラン情報取得
4. レスポンス返却

## ミドルウェア設計

### JWT 検証（middleware/auth.ts）

- `Authorization: Bearer <token>` からトークン抽出
- jose ライブラリで署名検証（HS256、シークレットは Workers Secrets）
- 検証失敗: `401 UNAUTHORIZED`
- 検証成功: `c.set('deviceId', payload.sub)` でコンテキストに格納

### レート制限（middleware/rateLimit.ts）

- KV Store で IP ベースのスライディングウィンドウ
- 制限: 60 req/min（AI処理）、120 req/min（その他）
- 超過時: `429 RATE_LIMITED`

### リクエストID（middleware/requestId.ts）

- `X-Request-ID` ヘッダーが存在すればそのまま使用
- 存在しなければ UUIDv4 を生成
- レスポンスヘッダーにも付与（トレーサビリティ）

## 月次使用量制限（services/quota.ts）

- **KV キー**: `quota:{deviceId}:{YYYY-MM}` (例: `quota:uuid-xxx:2026-03`)
- **値**: 整数（使用回数）
- **TTL**: 40日（月次リセットを自然に実現。古いキーは自動削除）
- **上限**: 15回/月（無料プラン）
- **Pro プラン**: 制限なし（null を返却）
- **リセット**: KV の TTL に依存。新しい月は新しいキーが生成される

## 環境構成

### wrangler.toml

```toml
name = "soyoka-api"
main = "src/index.ts"
compatibility_date = "2026-03-01"

[env.dev]
name = "soyoka-api-dev"
vars = { ENVIRONMENT = "dev" }
d1_databases = [{ binding = "DB", database_name = "soyoka-dev", database_id = "..." }]
kv_namespaces = [{ binding = "KV", id = "..." }]

[env.staging]
name = "soyoka-api-staging"
vars = { ENVIRONMENT = "staging" }
d1_databases = [{ binding = "DB", database_name = "soyoka-staging", database_id = "..." }]
kv_namespaces = [{ binding = "KV", id = "..." }]
```

### Secrets（wrangler secret put で設定）

| シークレット名 | 説明 |
|:-------------|:-----|
| `OPENAI_API_KEY` | OpenAI API キー（先ほど作成した Soyoka-dev キー） |
| `JWT_SECRET` | JWT 署名用シークレット（ランダム生成） |

### .dev.vars（ローカル開発用）

```
OPENAI_API_KEY=sk-proj-...
JWT_SECRET=local-dev-secret-32chars-minimum
```

## プライバシー・セキュリティ

- テキストデータは Workers のメモリ上でのみ処理し、D1/KV に永続化しない（REQ-008）
- OpenAI API への送信テキストは処理完了後に参照を破棄
- API キーはクライアント側に露出しない（NFR-008）
- JWT シークレットは Workers Secrets で管理
- CORS: iOS アプリからのリクエストのみ許可（Origin チェック不要、ネイティブアプリのため）

## エラーハンドリング

設計書 `03-backend-proxy.md` セクション 3.3 準拠。

| HTTPステータス | エラーコード | 条件 |
|:--------------|:-------------|:-----|
| 400 | `INVALID_REQUEST` | テキスト未入力、JSON不正 |
| 401 | `UNAUTHORIZED` | JWT 無効・期限切れ |
| 429 | `RATE_LIMITED` | IP レート制限超過 |
| 429 | `USAGE_LIMIT_EXCEEDED` | 月次15回到達 |
| 500 | `INTERNAL_ERROR` | サーバー内部エラー |
| 502 | `UPSTREAM_ERROR` | OpenAI API エラー（タイムアウト含む） |

## テスト戦略

- **Vitest** でユニットテスト + 統合テスト
- OpenAI API はモック（テスト時に実際の API を叩かない）
- D1/KV は Miniflare のインメモリモックを使用
- カバレッジ目標: 80%以上

## 受入基準

1. `wrangler dev` でローカル起動し、curl で全エンドポイントが動作すること
2. `wrangler deploy --env dev` で dev 環境にデプロイ成功
3. `wrangler deploy --env staging` で staging 環境にデプロイ成功
4. iOS アプリから dev 環境に接続し、AI 処理が E2E で動作すること
5. 月次使用量制限が正しく機能すること（16回目で 429）
6. レート制限が機能すること（61回/分で 429）
7. 全テストがパスすること
8. テキストデータが D1/KV に永続化されていないこと

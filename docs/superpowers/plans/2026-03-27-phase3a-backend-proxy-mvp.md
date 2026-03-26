# Phase 3a: Backend Proxy MVP 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cloudflare Workers 上に Backend Proxy MVP を構築し、iOS アプリから GPT-4o mini による AI 処理（要約+タグ+感情分析）を E2E で実行可能にする

**Architecture:** Cloudflare Workers + Hono + D1 Database + KV Store。デバイストークン認証 + JWT で保護された AI 処理エンドポイントを提供。

**Tech Stack:** TypeScript / Hono / Cloudflare Workers / D1 / KV / jose / Vitest / Zod

**Spec:** `docs/superpowers/specs/2026-03-27-phase3a-backend-proxy-mvp-design.md`

**Backend base path:** `repository/backend/`

---

## Task 1: Cloudflare Workers プロジェクト初期構築

**Files:**
- Create: `repository/backend/package.json`
- Create: `repository/backend/tsconfig.json`
- Create: `repository/backend/wrangler.toml`
- Create: `repository/backend/src/index.ts`
- Create: `repository/backend/src/types.ts`
- Create: `repository/backend/src/errors.ts`
- Create: `repository/backend/.dev.vars.example`
- Create: `repository/backend/.gitignore`
- Create: `repository/backend/vitest.config.ts`

- [ ] **Step 1: package.json を作成**

```json
{
  "name": "soyoka-api",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "deploy:dev": "wrangler deploy --env dev",
    "deploy:staging": "wrangler deploy --env staging",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "hono": "^4.7",
    "@hono/zod-validator": "^0.5",
    "jose": "^6.0",
    "zod": "^3.24"
  },
  "devDependencies": {
    "@cloudflare/vitest-pool-workers": "^0.8",
    "@cloudflare/workers-types": "^4.20260101",
    "vitest": "^3.0",
    "typescript": "^5.8",
    "wrangler": "^4.0"
  }
}
```

- [ ] **Step 2: tsconfig.json を作成**

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ESNext"],
    "types": ["@cloudflare/workers-types/2023-07-01", "@cloudflare/vitest-pool-workers"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist"
  },
  "include": ["src/**/*.ts", "test/**/*.ts"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 3: wrangler.toml を作成**

```toml
name = "soyoka-api"
main = "src/index.ts"
compatibility_date = "2026-03-01"

[env.dev]
name = "soyoka-api-dev"
vars = { ENVIRONMENT = "dev" }

[env.staging]
name = "soyoka-api-staging"
vars = { ENVIRONMENT = "staging" }
```

Note: D1/KV バインディングは `wrangler d1 create` / `wrangler kv namespace create` 後に ID を記入する。Task 2 で実行。

- [ ] **Step 4: src/types.ts を作成**

API リクエスト/レスポンスの型定義（Zod スキーマ含む）。設計書の JSON Schema 準拠。

- [ ] **Step 5: src/errors.ts を作成**

エラーコード定義とエラーレスポンス生成ヘルパー。

- [ ] **Step 6: src/index.ts を作成**

Hono アプリのエントリポイント。ルート定義（プレースホルダ）+ ヘルスチェック `GET /health`。

- [ ] **Step 7: .dev.vars.example と .gitignore を作成**

`.dev.vars.example`:
```
OPENAI_API_KEY=sk-proj-your-key-here
JWT_SECRET=local-dev-secret-minimum-32-characters
```

`.gitignore` に `.dev.vars`、`node_modules/`、`dist/`、`.wrangler/` を追加。

- [ ] **Step 8: npm install を実行**

```bash
cd repository/backend && npm install
```

- [ ] **Step 9: typecheck を実行**

```bash
npm run typecheck
```

- [ ] **Step 10: コミット**

```bash
git add repository/backend/
git commit -m "feat(backend): Cloudflare Workers + Hono プロジェクト初期構築

Soyoka Backend Proxy MVP の骨格を構築。
- Hono + TypeScript + Vitest の基本構成
- dev / staging 環境定義（wrangler.toml）
- 型定義・エラーコード・ヘルスチェックエンドポイント"
```

---

## Task 2: D1 Database + KV Store の作成と接続

**Files:**
- Create: `repository/backend/migrations/0001_initial.sql`
- Modify: `repository/backend/wrangler.toml`（D1/KV バインディング追加）
- Create: `repository/backend/src/bindings.ts`（Env 型定義）

- [ ] **Step 1: D1 データベースを作成（dev + staging）**

```bash
cd repository/backend
npx wrangler d1 create soyoka-dev
npx wrangler d1 create soyoka-staging
```

出力される database_id を wrangler.toml に記入。`migrations_dir = "migrations"` も各 D1 バインディングに追加すること。

- [ ] **Step 2: KV ネームスペースを作成（dev + staging）**

```bash
npx wrangler kv namespace create KV --env dev
npx wrangler kv namespace create KV --env staging
```

出力される id を wrangler.toml に記入。

- [ ] **Step 3: migrations/0001_initial.sql を作成**

```sql
-- devices テーブル: デバイス認証情報
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  plan TEXT NOT NULL DEFAULT 'free',
  app_version TEXT,
  os_version TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_devices_plan ON devices(plan);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_at);
```

- [ ] **Step 4: D1 マイグレーション実行**

```bash
npx wrangler d1 migrations apply soyoka-dev --env dev
npx wrangler d1 migrations apply soyoka-staging --env staging
```

- [ ] **Step 5: src/bindings.ts を作成**

Workers の Env 型定義（D1、KV、Secrets のバインディング）。

```typescript
export interface Env {
  DB: D1Database;
  KV: KVNamespace;
  OPENAI_API_KEY: string;
  JWT_SECRET: string;
  ENVIRONMENT: string;
}
```

- [ ] **Step 6: test/helpers/testUtils.ts を作成**

D1/KV のインメモリモック、テスト用 JWT 生成ヘルパー、テスト用 Hono アプリファクトリを定義。Task 3 以降のテストで共通利用する。

- [ ] **Step 7: wrangler.toml を更新**

D1 と KV のバインディングを env.dev / env.staging に追加。

- [ ] **Step 7: コミット**

```bash
git add repository/backend/
git commit -m "feat(backend): D1 Database + KV Store の作成とバインディング接続

- devices テーブルのマイグレーション（0001_initial.sql）
- dev / staging 環境の D1 + KV バインディング設定
- Env 型定義（bindings.ts）"
```

---

## Task 3: JWT トークンサービス実装

**Files:**
- Create: `repository/backend/src/services/token.ts`
- Create: `repository/backend/test/services/token.test.ts`

- [ ] **Step 1: テストを先に書く**

`test/services/token.test.ts`:
- `generateToken`: 有効な JWT を生成できること
- `verifyToken`: 有効な JWT を検証できること
- `verifyToken`: 期限切れの JWT を拒否すること
- `verifyToken`: 不正な署名の JWT を拒否すること

- [ ] **Step 2: src/services/token.ts を実装**

jose ライブラリで HS256 署名。
- `generateToken(deviceId: string, secret: string): Promise<{ token: string; expiresAt: Date }>`
- `verifyToken(token: string, secret: string): Promise<{ deviceId: string }>`
- 有効期限: 24時間

- [ ] **Step 3: テスト実行**

```bash
npm test -- --filter token
```

- [ ] **Step 4: コミット**

```bash
git commit -m "feat(backend): JWT トークン生成・検証サービスを実装

jose ライブラリで HS256 署名の JWT を生成・検証。
有効期限24h、sub にデバイスID を格納。"
```

---

## Task 4: デバイストークン認証エンドポイント実装

**Files:**
- Create: `repository/backend/src/routes/auth.ts`
- Create: `repository/backend/src/middleware/auth.ts`
- Create: `repository/backend/test/routes/auth.test.ts`
- Create: `repository/backend/test/middleware/auth.test.ts`

- [ ] **Step 1: テストを先に書く（auth route）**

- `POST /api/v1/auth/device`: 正常系 — JWT が返却されること
- `POST /api/v1/auth/device`: device_id 未指定 → 400
- `POST /api/v1/auth/device`: 不正な UUID 形式 → 400
- `POST /api/v1/auth/device`: 既存デバイス → last_seen_at 更新 + JWT 返却

- [ ] **Step 2: テストを先に書く（auth middleware）**

- 正常な JWT → deviceId がコンテキストに格納されること
- トークン未指定 → 401
- 不正トークン → 401
- 期限切れトークン → 401

- [ ] **Step 3: src/routes/auth.ts を実装**

POST /api/v1/auth/device ハンドラ。D1 upsert + JWT 生成。

- [ ] **Step 4: src/middleware/auth.ts を実装**

`Authorization: Bearer <token>` 検証ミドルウェア。

- [ ] **Step 5: src/index.ts にルートを追加**

auth ルートを Hono アプリに登録。/api/v1/auth/device は認証不要。

- [ ] **Step 6: テスト実行**

```bash
npm test -- --filter auth
```

- [ ] **Step 7: wrangler dev でローカル動作確認**

```bash
curl -X POST http://localhost:8787/api/v1/auth/device \
  -H "Content-Type: application/json" \
  -d '{"device_id":"550e8400-e29b-41d4-a716-446655440000","app_version":"1.0.0","os_version":"18.0"}'
```

- [ ] **Step 8: コミット**

```bash
git commit -m "feat(backend): デバイストークン認証エンドポイントと JWT ミドルウェアを実装

POST /api/v1/auth/device でデバイス登録 + JWT 発行。
Authorization ミドルウェアで全認証必須エンドポイントを保護。"
```

---

## Task 5: 月次使用量管理サービス実装

**Files:**
- Create: `repository/backend/src/services/quota.ts`
- Create: `repository/backend/test/services/quota.test.ts`

- [ ] **Step 1: テストを先に書く**

- `getUsage`: 使用量0の初期状態で `{ used: 0, limit: 15 }` を返すこと
- `getUsage`: 既存使用量がある場合に正しく返すこと
- `incrementUsage`: 使用量がインクリメントされること
- `checkQuota`: 上限未到達で true を返すこと
- `checkQuota`: 上限到達（15回）で false を返すこと
- `checkQuota`: Pro プランで常に true を返すこと
- KV キーが `usage:{deviceId}:{YYYY-MM}` 形式であること
- TTL が 40日に設定されること

- [ ] **Step 2: src/services/quota.ts を実装**

- `getUsage(kv, deviceId, plan)`: 現在の使用量を返却
- `incrementUsage(kv, deviceId)`: カウントを +1（TTL 40日）
- `checkQuota(kv, deviceId, plan)`: 上限チェック（free: 15, pro: 無制限）
- `getResetDate()`: 翌月1日 00:00 UTC を算出

- [ ] **Step 3: テスト実行**

```bash
npm test -- --filter quota
```

- [ ] **Step 4: コミット**

```bash
git commit -m "feat(backend): 月次使用量管理サービスを実装

KV Store で usage:{deviceId}:{YYYY-MM} 形式のカウントを管理。
無料プラン月15回制限、TTL 40日で自動リセット。"
```

---

## Task 6: OpenAI API クライアント + 統合プロンプト実装

**Files:**
- Create: `repository/backend/src/services/openai.ts`
- Create: `repository/backend/src/prompts/integrated.ts`
- Create: `repository/backend/test/services/openai.test.ts`

- [ ] **Step 1: src/prompts/integrated.ts を作成**

統合プロンプトテンプレート。1回の API 呼び出しで要約・タグ・感情分析を同時実行。
JSON 形式で出力を指定（設計書の JSON Schema 準拠）。

- [ ] **Step 2: テストを先に書く**

- `processAI`: 正常系 — OpenAI レスポンスを正しくパースすること
- `processAI`: options で summary=false の場合、要約なしで返すこと
- `processAI`: OpenAI API エラー → 502 UPSTREAM_ERROR
- `processAI`: OpenAI レスポンスの JSON パース失敗 → 500 INTERNAL_ERROR
- `processAI`: テキストが空 → 400 INVALID_REQUEST
- `processAI`: テキストが30000文字超 → 400 INVALID_REQUEST

- [ ] **Step 3: src/services/openai.ts を実装**

- `processAI(text, options, apiKey)`: OpenAI Chat Completions API を呼び出し
- モデル: `gpt-4o-mini`
- temperature: 0.3（安定した出力のため）
- response_format: `{ type: "json_object" }`（OpenAI JSON mode）
- タイムアウト: 30秒

- [ ] **Step 4: テスト実行**

```bash
npm test -- --filter openai
```

- [ ] **Step 5: コミット**

```bash
git commit -m "feat(backend): OpenAI APIクライアントと統合プロンプトを実装

GPT-4o mini で要約+タグ+感情分析を1回のAPI呼び出しで統合処理。
JSON形式出力、30秒タイムアウト、エラーハンドリング付き。"
```

---

## Task 7: AI 処理エンドポイント実装

**Files:**
- Create: `repository/backend/src/routes/ai.ts`
- Create: `repository/backend/test/routes/ai.test.ts`

- [ ] **Step 1: テストを先に書く**

- 正常系: 要約+タグ+感情分析が返却されること
- 正常系: usage 情報が含まれること
- 認証なし → 401
- テキスト未入力 → 400
- テキスト30000文字超 → 400
- 無料プラン月次上限到達 → 429 USAGE_LIMIT_EXCEEDED
- OpenAI エラー → 502 UPSTREAM_ERROR
- 処理成功後に使用量がインクリメントされること

- [ ] **Step 2: src/routes/ai.ts を実装**

設計書の処理フロー10ステップに準拠。

- [ ] **Step 3: src/index.ts にルートを追加**

ai ルートを Hono アプリに登録。認証ミドルウェアを適用。

- [ ] **Step 4: テスト実行**

```bash
npm test -- --filter ai
```

- [ ] **Step 5: コミット**

```bash
git commit -m "feat(backend): AI処理エンドポイント（POST /api/v1/ai/process）を実装

GPT-4o mini で要約+タグ+感情分析の統合処理。
月次使用量チェック、認証、エラーハンドリング付き。
テキストデータはメモリ上のみで処理し永続化しない。"
```

---

## Task 8: 使用量確認エンドポイント + レート制限ミドルウェア実装

**Files:**
- Create: `repository/backend/src/routes/usage.ts`
- Create: `repository/backend/src/middleware/rateLimit.ts`
- Create: `repository/backend/src/middleware/requestId.ts`
- Create: `repository/backend/test/routes/usage.test.ts`
- Create: `repository/backend/test/middleware/rateLimit.test.ts`

- [ ] **Step 1: テストを先に書く（usage route）**

- 正常系: 使用量情報が返却されること
- 認証なし → 401
- Pro プラン: limit が null であること

- [ ] **Step 2: テストを先に書く（rateLimit middleware）**

- 制限内: リクエスト通過
- 制限超過: 429 RATE_LIMITED
- 異なる IP: 独立してカウントされること

- [ ] **Step 3: 各ファイルを実装**

- usage route: JWT 検証 → KV/D1 から情報取得 → レスポンス
- rateLimit: KV ベースのスライディングウィンドウ（60 req/min for AI, 120 req/min for others）
- requestId: X-Request-ID 検証・生成

- [ ] **Step 4: src/index.ts に全ミドルウェア・ルートを統合**

全ルートとミドルウェアを統合:
```
/health              → 認証不要
/api/v1/auth/device  → 認証不要、レート制限あり
/api/v1/ai/process   → 認証必須、レート制限あり（60 req/min）
/api/v1/usage        → 認証必須、レート制限あり
```

- [ ] **Step 5: テスト実行**

```bash
npm test
```
全テストパスを確認。

- [ ] **Step 6: コミット**

```bash
git commit -m "feat(backend): 使用量確認エンドポイントとレート制限ミドルウェアを実装

GET /api/v1/usage で月次使用量を確認。
KVベースのスライディングウィンドウでレート制限。
X-Request-ID によるリクエストトレーサビリティ。"
```

---

## Task 9: ローカル動作確認 + E2E テスト

**Files:**
- Create: `repository/backend/test/e2e/full-flow.test.ts`
- Create: `repository/backend/.dev.vars`（ローカルのみ、gitignore 対象）

- [ ] **Step 1: .dev.vars にシークレットを設定**

```
OPENAI_API_KEY=sk-proj-（実際のキー）
JWT_SECRET=local-dev-secret-minimum-32-characters-long
```

- [ ] **Step 2: E2E テストを作成**

フルフローテスト:
1. POST /api/v1/auth/device → JWT 取得
2. GET /api/v1/usage → used: 0
3. POST /api/v1/ai/process → AI 処理結果取得
4. GET /api/v1/usage → used: 1
5. 15回繰り返し → 16回目で 429

- [ ] **Step 3: wrangler dev でローカル動作確認**

curl で全エンドポイントの動作を確認。

- [ ] **Step 4: テスト実行（E2E 含む）**

```bash
npm test
```

- [ ] **Step 5: コミット**

```bash
git commit -m "test(backend): E2Eテストとローカル動作確認

デバイス認証→AI処理→使用量確認のフルフローテスト。
月次使用量制限の動作確認（16回目で429）。"
```

---

## Task 10: dev + staging 環境デプロイ

- [ ] **Step 1: Secrets を設定**

```bash
cd repository/backend
npx wrangler secret put OPENAI_API_KEY --env dev
npx wrangler secret put JWT_SECRET --env dev
npx wrangler secret put OPENAI_API_KEY --env staging
npx wrangler secret put JWT_SECRET --env staging
```

- [ ] **Step 2: dev 環境にデプロイ**

```bash
npm run deploy:dev
```

デプロイ URL を記録。

- [ ] **Step 3: dev 環境で curl テスト**

```bash
# デバイス登録
curl -X POST https://soyoka-api-dev.<account>.workers.dev/api/v1/auth/device \
  -H "Content-Type: application/json" \
  -d '{"device_id":"test-uuid-001","app_version":"1.0.0","os_version":"18.0"}'

# AI 処理
curl -X POST https://soyoka-api-dev.<account>.workers.dev/api/v1/ai/process \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <取得したJWT>" \
  -d '{"text":"今日はプロジェクトのミーティングがあって、進捗を共有しました。来週のリリースに向けて最終確認をしました。"}'
```

- [ ] **Step 4: staging 環境にデプロイ**

```bash
npm run deploy:staging
```

- [ ] **Step 5: staging 環境で curl テスト**

dev と同じテストを staging URL で実行。

- [ ] **Step 6: コミット（デプロイ URL を docs に記録）**

```bash
git commit -m "chore(backend): dev + staging 環境にデプロイ完了

- dev: https://soyoka-api-dev.xxx.workers.dev
- staging: https://soyoka-api-staging.xxx.workers.dev
- Secrets 設定済み（OPENAI_API_KEY, JWT_SECRET）"
```

---

## 実行順序と依存関係

```
Task 1 (プロジェクト構築)
  ↓
Task 2 (D1/KV 作成)
  ↓
Task 3 (JWT サービス)
  ↓
Task 4 (認証エンドポイント + ミドルウェア)
  ↓
Task 5 (月次使用量サービス)
  ↓
Task 6 (OpenAI クライアント + プロンプト)
  ↓
Task 7 (AI 処理エンドポイント) ← Task 4,5,6 に依存
  ↓
Task 8 (使用量エンドポイント + レート制限)
  ↓
Task 9 (E2E テスト)
  ↓
Task 10 (デプロイ)
```

## 完了後の検証

- [ ] 全テストパス
- [ ] dev 環境で E2E 動作確認
- [ ] staging 環境で E2E 動作確認
- [ ] spec-gate レビュー（新規spawn）
- [ ] code-reviewer 実行（新規spawn）

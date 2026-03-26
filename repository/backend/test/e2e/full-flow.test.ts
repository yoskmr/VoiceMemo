import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import type { Env } from "../../src/types.js";
import { authRoutes } from "../../src/routes/auth.js";
import { aiRoutes } from "../../src/routes/ai.js";
import { usageRoutes } from "../../src/routes/usage.js";
import { requestIdMiddleware } from "../../src/middleware/requestId.js";
import { createRateLimitMiddleware } from "../../src/middleware/rateLimit.js";
import { createErrorResponse, ErrorCode } from "../../src/errors.js";

// --- Mock Data ---

const VALID_AI_RESPONSE = {
  summary: {
    title: "E2Eテスト要約",
    brief: "これはE2Eテストの要約です",
    key_points: ["要点1", "要点2"],
  },
  tags: [
    { label: "E2Eテスト", confidence: 0.95 },
    { label: "フルフロー", confidence: 0.80 },
  ],
  sentiment: {
    primary: "joy",
    scores: {
      joy: 0.6,
      sadness: 0.05,
      anger: 0.0,
      fear: 0.0,
      surprise: 0.1,
      disgust: 0.0,
      anticipation: 0.15,
      trust: 0.1,
    },
    evidence: ["嬉しいテキスト"],
  },
};

function createMockOpenAIFetchResponse(content: unknown): Response {
  return new Response(
    JSON.stringify({
      id: "chatcmpl-e2e-test",
      object: "chat.completion",
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: JSON.stringify(content),
          },
          finish_reason: "stop",
        },
      ],
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}

// --- D1 Mock ---

interface MockDevice {
  id: string;
  plan: string;
  app_version: string;
  os_version: string;
  created_at: string;
  last_seen_at: string;
}

function createMockD1(): D1Database {
  const store = new Map<string, MockDevice>();

  const mockD1 = {
    prepare: (sql: string) => {
      let boundValues: unknown[] = [];
      return {
        bind: (...values: unknown[]) => {
          boundValues = values;
          return {
            run: async () => {
              if (sql.includes("INSERT INTO devices")) {
                const [id, app_version, os_version] = boundValues as [string, string, string];
                const existing = store.get(id);
                if (existing) {
                  existing.app_version = app_version;
                  existing.os_version = os_version;
                  existing.last_seen_at = new Date().toISOString();
                } else {
                  store.set(id, {
                    id,
                    plan: "free",
                    app_version,
                    os_version,
                    created_at: new Date().toISOString(),
                    last_seen_at: new Date().toISOString(),
                  });
                }
              }
              return { success: true, results: [], meta: {} };
            },
            first: async () => {
              if (sql.includes("SELECT plan FROM devices")) {
                const [id] = boundValues as [string];
                const device = store.get(id);
                return device ? { plan: device.plan } : null;
              }
              if (sql.includes("SELECT * FROM devices")) {
                const [id] = boundValues as [string];
                return store.get(id) ?? null;
              }
              return null;
            },
          };
        },
        run: async () => ({ success: true, results: [], meta: {} }),
        first: async () => null,
      };
    },
    dump: async () => new ArrayBuffer(0),
    batch: async () => [],
    exec: async () => ({ count: 0, duration: 0 }),
  } as unknown as D1Database;

  return mockD1;
}

// --- KV Mock ---

function createMockKV(): KVNamespace & { _store: Map<string, { value: string; ttl?: number }> } {
  const store = new Map<string, { value: string; ttl?: number }>();

  return {
    _store: store,
    get: async (key: string) => {
      const entry = store.get(key);
      return entry?.value ?? null;
    },
    put: async (key: string, value: string, options?: { expirationTtl?: number }) => {
      store.set(key, { value, ttl: options?.expirationTtl });
    },
    delete: async (key: string) => {
      store.delete(key);
    },
    list: async () => ({ keys: [], list_complete: true, cacheStatus: null }),
    getWithMetadata: async (key: string) => {
      const entry = store.get(key);
      return { value: entry?.value ?? null, metadata: null, cacheStatus: null };
    },
  } as unknown as KVNamespace & { _store: Map<string, { value: string; ttl?: number }> };
}

// --- Test Constants ---

const TEST_SECRET = "test-secret-key-for-unit-tests-only";
const DEVICE_ID = "660e8400-e29b-41d4-a716-446655440001";

// --- Helpers ---

function getYearMonth(): string {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

// --- Full App Factory (全ルートを統合) ---

interface AppOptions {
  kv?: ReturnType<typeof createMockKV>;
  db?: D1Database;
}

function createFullApp(options: AppOptions = {}): Hono {
  const app = new Hono<{ Bindings: Env }>();

  const db = options.db ?? createMockD1();
  const kv = options.kv ?? createMockKV();

  // env 注入ミドルウェア
  app.use("*", async (c, next) => {
    c.env = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: TEST_SECRET,
      DB: db,
      KV: kv,
    } as Env;
    await next();
  });

  // requestId ミドルウェア
  app.use("*", requestIdMiddleware);

  // ヘルスチェック
  app.get("/health", (c) => {
    return c.json({
      status: "ok",
      environment: c.env.ENVIRONMENT ?? "unknown",
    });
  });

  // 認証ルート
  app.use("/api/v1/auth/*", createRateLimitMiddleware({ maxRequests: 120 }));
  app.route("/api/v1/auth", authRoutes);

  // AI ルート
  app.use("/api/v1/ai/*", createRateLimitMiddleware({ maxRequests: 60 }));
  app.route("/api/v1/ai", aiRoutes);

  // 使用量ルート
  app.use("/api/v1/usage", createRateLimitMiddleware({ maxRequests: 120 }));
  app.use("/api/v1/usage/*", createRateLimitMiddleware({ maxRequests: 120 }));
  app.route("/api/v1/usage", usageRoutes);

  // エラーハンドラー
  app.onError((err, c) => {
    if (err instanceof HTTPException && err.res !== undefined) {
      return err.res;
    }
    const requestId = crypto.randomUUID();
    const body = createErrorResponse(
      ErrorCode.INTERNAL_ERROR,
      "An unexpected error occurred",
      requestId,
    );
    return c.json(body, 500);
  });

  return app;
}

// --- Tests ---

describe("E2E: 認証 → AI処理 → 使用量確認のフルフロー", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("認証 → 使用量確認(0) → AI処理 → 使用量確認(1)", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      createMockOpenAIFetchResponse(VALID_AI_RESPONSE),
    );

    const app = createFullApp();

    // Step 1: POST /api/v1/auth/device → JWT 取得
    const authRes = await app.request("/api/v1/auth/device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        device_id: DEVICE_ID,
        app_version: "1.0.0",
        os_version: "18.0",
      }),
    });

    expect(authRes.status).toBe(200);

    const authBody = await authRes.json() as {
      access_token: string;
      expires_at: string;
      device_id: string;
    };
    expect(authBody.access_token).toBeDefined();
    expect(authBody.device_id).toBe(DEVICE_ID);

    const authHeader = `Bearer ${authBody.access_token}`;

    // Step 2: GET /api/v1/usage → used: 0, limit: 15
    const usageRes1 = await app.request("/api/v1/usage", {
      method: "GET",
      headers: { Authorization: authHeader },
    });

    expect(usageRes1.status).toBe(200);

    const usageBody1 = await usageRes1.json() as {
      used: number;
      limit: number | null;
      plan: string;
      resets_at: string | null;
    };
    expect(usageBody1.used).toBe(0);
    expect(usageBody1.limit).toBe(15);
    expect(usageBody1.plan).toBe("free");

    // Step 3: POST /api/v1/ai/process（モック OpenAI レスポンス）→ AI 処理結果取得
    const aiRes = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: authHeader,
      },
      body: JSON.stringify({
        text: "今日はとても良い天気で気分が良いです。E2Eテストです。",
        language: "ja",
      }),
    });

    expect(aiRes.status).toBe(200);

    const aiBody = await aiRes.json() as Record<string, unknown>;
    expect(aiBody.summary).toBeDefined();
    expect(aiBody.tags).toBeDefined();
    expect(aiBody.sentiment).toBeDefined();

    const aiUsage = aiBody.usage as Record<string, unknown>;
    expect(aiUsage.used).toBe(1);
    expect(aiUsage.limit).toBe(15);
    expect(aiUsage.plan).toBe("free");

    const metadata = aiBody.metadata as Record<string, unknown>;
    expect(metadata.model).toBe("gpt-4o-mini");
    expect(metadata.provider).toBe("cloud_gpt4o_mini");

    // Step 4: GET /api/v1/usage → used: 1, limit: 15
    const usageRes2 = await app.request("/api/v1/usage", {
      method: "GET",
      headers: { Authorization: authHeader },
    });

    expect(usageRes2.status).toBe(200);

    const usageBody2 = await usageRes2.json() as {
      used: number;
      limit: number | null;
    };
    expect(usageBody2.used).toBe(1);
    expect(usageBody2.limit).toBe(15);
  });
});

describe("E2E: 月次上限到達", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("KVに15回分をセット → AI処理で429 → 使用量で15を確認", async () => {
    const kv = createMockKV();

    // Step 1: POST /api/v1/auth/device → JWT 取得
    const app = createFullApp({ kv });

    const authRes = await app.request("/api/v1/auth/device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        device_id: DEVICE_ID,
        app_version: "1.0.0",
        os_version: "18.0",
      }),
    });

    expect(authRes.status).toBe(200);

    const authBody = await authRes.json() as { access_token: string };
    const authHeader = `Bearer ${authBody.access_token}`;

    // Step 2: KV に usage:{deviceId}:{YYYY-MM} = 15 を直接セット
    const yearMonth = getYearMonth();
    kv._store.set(`usage:${DEVICE_ID}:${yearMonth}`, { value: "15" });

    // Step 3: POST /api/v1/ai/process → 429 USAGE_LIMIT_EXCEEDED
    const aiRes = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: authHeader,
      },
      body: JSON.stringify({
        text: "上限到達テスト",
        language: "ja",
      }),
    });

    expect(aiRes.status).toBe(429);

    const aiBody = await aiRes.json() as { error: { code: string } };
    expect(aiBody.error.code).toBe("USAGE_LIMIT_EXCEEDED");

    // Step 4: GET /api/v1/usage → used: 15, limit: 15
    const usageRes = await app.request("/api/v1/usage", {
      method: "GET",
      headers: { Authorization: authHeader },
    });

    expect(usageRes.status).toBe(200);

    const usageBody = await usageRes.json() as {
      used: number;
      limit: number | null;
    };
    expect(usageBody.used).toBe(15);
    expect(usageBody.limit).toBe(15);
  });
});

describe("E2E: ヘルスチェック", () => {
  it("GET /health → { status: 'ok' }", async () => {
    const app = createFullApp();

    const res = await app.request("/health", {
      method: "GET",
    });

    expect(res.status).toBe(200);

    const body = await res.json() as { status: string; environment: string };
    expect(body.status).toBe("ok");
    expect(body.environment).toBe("test");
  });
});

describe("E2E: 未認証リクエスト", () => {
  it("POST /api/v1/ai/process（Authorization なし）→ 401", async () => {
    const app = createFullApp();

    const res = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: "未認証テスト",
        language: "ja",
      }),
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("GET /api/v1/usage（Authorization なし）→ 401", async () => {
    const app = createFullApp();

    const res = await app.request("/api/v1/usage", {
      method: "GET",
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });
});

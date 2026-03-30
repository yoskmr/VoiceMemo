import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import type { Env } from "../../src/types.js";
import { jwtAuthMiddleware, type AuthEnv } from "../../src/middleware/auth.js";
import { generateToken } from "../../src/services/token.js";

// --- Mock KV ---

function createMockKV(): KVNamespace {
  return {
    get: async () => null,
    put: async () => {},
    delete: async () => {},
    list: async () => ({ keys: [], list_complete: true, cacheStatus: null }),
    getWithMetadata: async () => ({ value: null, metadata: null, cacheStatus: null }),
  } as unknown as KVNamespace;
}

// --- Mock D1 ---

function createMockD1(): D1Database {
  return {
    prepare: () => ({
      bind: () => ({
        run: async () => ({ success: true, results: [], meta: {} }),
        first: async () => null,
      }),
      run: async () => ({ success: true, results: [], meta: {} }),
      first: async () => null,
    }),
    dump: async () => new ArrayBuffer(0),
    batch: async () => [],
    exec: async () => ({ count: 0, duration: 0 }),
  } as unknown as D1Database;
}

// --- Test Constants ---

const TEST_SECRET = "test-secret-key-for-unit-tests-only";
const TEST_DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000";

// --- Test Setup ---

function createApp(): Hono<AuthEnv> {
  const app = new Hono<AuthEnv>();

  // テスト用 env を注入
  app.use("*", async (c, next) => {
    (c.env as Env) = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: TEST_SECRET,
      DB: createMockD1(),
      KV: createMockKV(),
    };
    await next();
  });

  // 認証ミドルウェアを適用
  app.use("/protected/*", jwtAuthMiddleware);

  // テスト用の保護されたルート
  app.get("/protected/me", (c) => {
    const deviceId = c.get("deviceId");
    return c.json({ device_id: deviceId });
  });

  return app;
}

// --- Tests ---

describe("JWT auth middleware", () => {
  it("有効な JWT でコンテキストに deviceId を格納する", async () => {
    const app = createApp();
    const { token } = await generateToken(TEST_DEVICE_ID, TEST_SECRET);

    const res = await app.request("/protected/me", {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    });

    expect(res.status).toBe(200);

    const body = await res.json() as { device_id: string };
    expect(body.device_id).toBe(TEST_DEVICE_ID);
  });

  it("Authorization ヘッダー未指定で 401 を返却する", async () => {
    const app = createApp();

    const res = await app.request("/protected/me", {
      method: "GET",
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("Bearer プレフィックスなしで 401 を返却する", async () => {
    const app = createApp();
    const { token } = await generateToken(TEST_DEVICE_ID, TEST_SECRET);

    const res = await app.request("/protected/me", {
      method: "GET",
      headers: { Authorization: token },
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("不正なトークンで 401 を返却する", async () => {
    const app = createApp();

    const res = await app.request("/protected/me", {
      method: "GET",
      headers: { Authorization: "Bearer invalid.jwt.token" },
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("異なるシークレットで署名されたトークンで 401 を返却する", async () => {
    const app = createApp();
    const { token } = await generateToken(TEST_DEVICE_ID, "different-secret-key");

    const res = await app.request("/protected/me", {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });
});

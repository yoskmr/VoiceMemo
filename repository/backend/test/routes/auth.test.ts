import { describe, it, expect, beforeEach } from "vitest";
import { Hono } from "hono";
import type { Env } from "../../src/types.js";
import { authRoutes } from "../../src/routes/auth.js";
import { verifyToken } from "../../src/services/token.js";

// --- D1 Mock ---

interface MockDevice {
  id: string;
  plan: string;
  app_version: string | null;
  os_version: string | null;
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
                  // ON CONFLICT → UPDATE
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
              const [id] = boundValues as [string];
              return store.get(id) ?? null;
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

// --- Test Constants ---

const TEST_SECRET = "test-secret-key-for-unit-tests-only";
const VALID_DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000";

// --- Test Setup ---

function createApp(): Hono<{ Bindings: Env }> {
  const app = new Hono<{ Bindings: Env }>();

  // テスト用 env を注入
  app.use("*", async (c, next) => {
    c.env = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: TEST_SECRET,
      DB: createMockD1(),
      KV: createMockKV(),
    } as Env;
    await next();
  });

  app.route("/api/v1/auth", authRoutes);

  return app;
}

// --- Tests ---

describe("POST /api/v1/auth/device", () => {
  let app: Hono<{ Bindings: Env }>;

  beforeEach(() => {
    app = createApp();
  });

  it("正常系: デバイス認証で JWT を返却する", async () => {
    const res = await app.request("/api/v1/auth/device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        device_id: VALID_DEVICE_ID,
        app_version: "1.0.0",
        os_version: "18.0",
      }),
    });

    expect(res.status).toBe(200);

    const body = await res.json() as {
      access_token: string;
      expires_at: string;
      device_id: string;
    };
    expect(body.access_token).toBeDefined();
    expect(body.expires_at).toBeDefined();
    expect(body.device_id).toBe(VALID_DEVICE_ID);

    // トークンが有効であること
    const verified = await verifyToken(body.access_token, TEST_SECRET);
    expect(verified.deviceId).toBe(VALID_DEVICE_ID);
  });

  it("device_id 未指定で 400 を返却する", async () => {
    const res = await app.request("/api/v1/auth/device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        app_version: "1.0.0",
        os_version: "18.0",
      }),
    });

    expect(res.status).toBe(400);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });

  it("不正な UUID で 400 を返却する", async () => {
    const res = await app.request("/api/v1/auth/device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        device_id: "not-a-valid-uuid",
        app_version: "1.0.0",
        os_version: "18.0",
      }),
    });

    expect(res.status).toBe(400);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });

  it("既存デバイスの再認証で更新される", async () => {
    // 1 回目の認証
    const res1 = await app.request("/api/v1/auth/device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        device_id: VALID_DEVICE_ID,
        app_version: "1.0.0",
        os_version: "18.0",
      }),
    });
    expect(res1.status).toBe(200);

    // 2 回目の認証（バージョン更新）
    const res2 = await app.request("/api/v1/auth/device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        device_id: VALID_DEVICE_ID,
        app_version: "2.0.0",
        os_version: "19.0",
      }),
    });
    expect(res2.status).toBe(200);

    const body = await res2.json() as {
      access_token: string;
      device_id: string;
    };
    expect(body.device_id).toBe(VALID_DEVICE_ID);
    expect(body.access_token).toBeDefined();
  });
});

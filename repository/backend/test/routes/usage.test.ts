import { describe, it, expect, beforeEach } from "vitest";
import { Hono } from "hono";
import type { Env } from "../../src/types.js";
import { usageRoutes } from "../../src/routes/usage.js";
import { generateToken } from "../../src/services/token.js";

// --- Mock D1 ---

interface MockDevice {
  id: string;
  plan: string;
}

function createMockD1(devices: MockDevice[] = []): D1Database {
  const deviceMap = new Map(devices.map((d) => [d.id, d]));

  return {
    prepare: (sql: string) => {
      let boundValues: unknown[] = [];
      return {
        bind: (...values: unknown[]) => {
          boundValues = values;
          return {
            run: async () => ({ success: true, results: [], meta: {} }),
            first: async () => {
              if (sql.includes("SELECT plan FROM devices")) {
                const [id] = boundValues as [string];
                const device = deviceMap.get(id);
                return device ? { plan: device.plan } : null;
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
}

// --- Mock KV ---

function createMockKV(
  initialData: Record<string, string> = {},
): KVNamespace {
  const store = new Map<string, string>(Object.entries(initialData));

  return {
    get: async (key: string) => store.get(key) ?? null,
    put: async (key: string, value: string) => { store.set(key, value); },
    delete: async (key: string) => { store.delete(key); },
    list: async () => ({ keys: [], list_complete: true, cacheStatus: null }),
    getWithMetadata: async (key: string) => ({
      value: store.get(key) ?? null,
      metadata: null,
      cacheStatus: null,
    }),
  } as unknown as KVNamespace;
}

// --- Test Constants ---

const TEST_SECRET = "test-secret-key-for-unit-tests-only";
const DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000";

// --- Test Setup ---

interface AppOptions {
  devices?: MockDevice[];
  kvData?: Record<string, string>;
}

function createApp(options: AppOptions = {}): Hono<{ Bindings: Env }> {
  const app = new Hono<{ Bindings: Env }>();

  const devices = options.devices ?? [{ id: DEVICE_ID, plan: "free" }];
  const kv = createMockKV(options.kvData ?? {});

  app.use("*", async (c, next) => {
    c.env = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: TEST_SECRET,
      DB: createMockD1(devices),
      KV: kv,
    } as Env;
    await next();
  });

  app.route("/api/v1/usage", usageRoutes);

  return app;
}

async function getAuthHeader(): Promise<string> {
  const { token } = await generateToken(DEVICE_ID, TEST_SECRET);
  return `Bearer ${token}`;
}

// --- Tests ---

describe("GET /api/v1/usage", () => {
  it("正常系: 無料プランの使用量情報を返却する", async () => {
    const app = createApp();
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/usage", {
      method: "GET",
      headers: { Authorization: auth },
    });

    expect(res.status).toBe(200);

    const body = await res.json() as {
      used: number;
      limit: number | null;
      plan: string;
      resets_at: string | null;
    };

    expect(body.used).toBe(0);
    expect(body.limit).toBe(15);
    expect(body.plan).toBe("free");
    expect(body.resets_at).toBeDefined();
    expect(body.resets_at).not.toBeNull();
  });

  it("認証なしで 401 を返却する", async () => {
    const app = createApp();

    const res = await app.request("/api/v1/usage", {
      method: "GET",
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("Pro プランで limit: null, resets_at: null を返却する", async () => {
    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "pro" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/usage", {
      method: "GET",
      headers: { Authorization: auth },
    });

    expect(res.status).toBe(200);

    const body = await res.json() as {
      used: number;
      limit: number | null;
      plan: string;
      resets_at: string | null;
    };

    expect(body.used).toBe(0);
    expect(body.limit).toBeNull();
    expect(body.plan).toBe("pro");
    expect(body.resets_at).toBeNull();
  });

  it("使用済みカウントが反映される", async () => {
    // KV に使用量データを事前設定
    const yearMonth = (() => {
      const now = new Date();
      const year = now.getUTCFullYear();
      const month = String(now.getUTCMonth() + 1).padStart(2, "0");
      return `${year}-${month}`;
    })();

    const app = createApp({
      kvData: { [`usage:${DEVICE_ID}:${yearMonth}`]: "5" },
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/usage", {
      method: "GET",
      headers: { Authorization: auth },
    });

    expect(res.status).toBe(200);

    const body = await res.json() as { used: number };
    expect(body.used).toBe(5);
  });
});

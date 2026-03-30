import { describe, it, expect, beforeEach } from "vitest";
import { Hono } from "hono";
import type { Env } from "../../src/types.js";
import { createRateLimitMiddleware } from "../../src/middleware/rateLimit.js";

// --- Mock KV ---

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

// --- Test Setup ---

function createApp(kv: KVNamespace, maxRequests: number): Hono {
  const app = new Hono<{ Bindings: Env }>();

  app.use("*", async (c, next) => {
    c.env = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: "test-secret",
      DB: createMockD1(),
      KV: kv,
    } as Env;
    await next();
  });

  app.use("/test/*", createRateLimitMiddleware({ maxRequests }));

  app.get("/test/endpoint", (c) => {
    return c.json({ status: "ok" });
  });

  return app;
}

// --- Tests ---

describe("rateLimit middleware", () => {
  let kv: ReturnType<typeof createMockKV>;

  beforeEach(() => {
    kv = createMockKV();
  });

  it("制限内のリクエストを通過させる", async () => {
    const app = createApp(kv, 5);

    const res = await app.request("/test/endpoint", {
      method: "GET",
      headers: { "X-Forwarded-For": "192.168.1.1" },
    });

    expect(res.status).toBe(200);

    const body = await res.json() as { status: string };
    expect(body.status).toBe("ok");

    // レート制限ヘッダーが付与される
    expect(res.headers.get("X-RateLimit-Limit")).toBe("5");
    expect(res.headers.get("X-RateLimit-Remaining")).toBe("4");
  });

  it("制限超過で 429 RATE_LIMITED を返却する", async () => {
    const app = createApp(kv, 3);

    // 3回のリクエストを実行（制限いっぱいまで）
    for (let i = 0; i < 3; i++) {
      const res = await app.request("/test/endpoint", {
        method: "GET",
        headers: { "X-Forwarded-For": "192.168.1.1" },
      });
      expect(res.status).toBe(200);
    }

    // 4回目で制限超過
    const res = await app.request("/test/endpoint", {
      method: "GET",
      headers: { "X-Forwarded-For": "192.168.1.1" },
    });

    expect(res.status).toBe(429);

    const body = await res.json() as { error: { code: string; details?: Record<string, unknown> } };
    expect(body.error.code).toBe("RATE_LIMITED");

    // Retry-After ヘッダー
    expect(res.headers.get("Retry-After")).toBe("60");
  });

  it("異なるIPは独立してカウントされる", async () => {
    const app = createApp(kv, 2);

    // IP1 から 2 回
    for (let i = 0; i < 2; i++) {
      const res = await app.request("/test/endpoint", {
        method: "GET",
        headers: { "X-Forwarded-For": "192.168.1.1" },
      });
      expect(res.status).toBe(200);
    }

    // IP1 は制限超過
    const resBlocked = await app.request("/test/endpoint", {
      method: "GET",
      headers: { "X-Forwarded-For": "192.168.1.1" },
    });
    expect(resBlocked.status).toBe(429);

    // IP2 はまだ通過できる
    const resOk = await app.request("/test/endpoint", {
      method: "GET",
      headers: { "X-Forwarded-For": "192.168.1.2" },
    });
    expect(resOk.status).toBe(200);
  });

  it("Remaining が正しくデクリメントされる", async () => {
    const app = createApp(kv, 5);

    const res1 = await app.request("/test/endpoint", {
      method: "GET",
      headers: { "X-Forwarded-For": "10.0.0.1" },
    });
    expect(res1.headers.get("X-RateLimit-Remaining")).toBe("4");

    const res2 = await app.request("/test/endpoint", {
      method: "GET",
      headers: { "X-Forwarded-For": "10.0.0.1" },
    });
    expect(res2.headers.get("X-RateLimit-Remaining")).toBe("3");

    const res3 = await app.request("/test/endpoint", {
      method: "GET",
      headers: { "X-Forwarded-For": "10.0.0.1" },
    });
    expect(res3.headers.get("X-RateLimit-Remaining")).toBe("2");
  });
});

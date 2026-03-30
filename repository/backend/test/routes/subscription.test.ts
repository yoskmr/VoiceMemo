import { describe, it, expect, beforeEach } from "vitest";
import { Hono } from "hono";
import type { Env } from "../../src/types.js";
import { subscriptionRoutes } from "../../src/routes/subscription.js";
import { generateToken } from "../../src/services/token.js";

// --- D1 Mock ---

interface MockDevice {
  id: string;
  plan: string;
  product_id: string | null;
  subscription_expires_at: string | null;
  original_transaction_id: string | null;
}

function createMockD1(): D1Database & { _devices: Map<string, MockDevice> } {
  const devices = new Map<string, MockDevice>();

  const mockD1 = {
    _devices: devices,
    prepare: (sql: string) => {
      let boundValues: unknown[] = [];
      return {
        bind: (...values: unknown[]) => {
          boundValues = values;
          return {
            run: async () => {
              if (sql.includes("UPDATE devices") && sql.includes("plan = 'pro'")) {
                // verify: plan を pro に更新
                const [productId, expiresAt, origTxId, deviceId] = boundValues as [string, string, string, string];
                const device = devices.get(deviceId);
                if (device) {
                  device.plan = "pro";
                  device.product_id = productId;
                  device.subscription_expires_at = expiresAt;
                  device.original_transaction_id = origTxId;
                }
              } else if (sql.includes("UPDATE devices") && sql.includes("plan = 'free'")) {
                // webhook EXPIRED/REVOKE: plan を free に戻す
                const [origTxId] = boundValues as [string];
                for (const device of devices.values()) {
                  if (device.original_transaction_id === origTxId) {
                    device.plan = "free";
                    device.subscription_expires_at = null;
                  }
                }
              }
              return { success: true, results: [], meta: {} };
            },
            first: async () => {
              const [id] = boundValues as [string];
              return devices.get(id) ?? null;
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
  } as unknown as D1Database & { _devices: Map<string, MockDevice> };

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
const DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000";

// --- Test Setup ---

function createApp(mockD1?: ReturnType<typeof createMockD1>): {
  app: Hono;
  db: ReturnType<typeof createMockD1>;
} {
  const app = new Hono<{ Bindings: Env }>();
  const db = mockD1 ?? createMockD1();

  app.use("*", async (c, next) => {
    c.env = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: TEST_SECRET,
      DB: db,
      KV: createMockKV(),
    } as Env;
    await next();
  });

  app.route("/api/v1/subscription", subscriptionRoutes);

  return { app, db };
}

async function getAuthHeader(): Promise<string> {
  const { token } = await generateToken(DEVICE_ID, TEST_SECRET);
  return `Bearer ${token}`;
}

// --- Tests ---

describe("POST /api/v1/subscription/verify", () => {
  let app: Hono;
  let db: ReturnType<typeof createMockD1>;

  beforeEach(() => {
    const created = createApp();
    app = created.app;
    db = created.db;

    // テスト用デバイスを D1 に登録
    db._devices.set(DEVICE_ID, {
      id: DEVICE_ID,
      plan: "free",
      product_id: null,
      subscription_expires_at: null,
      original_transaction_id: null,
    });
  });

  it("正常系: トランザクション検証で plan を pro に更新する", async () => {
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/subscription/verify", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({
        transaction_id: "tx-12345",
        product_id: "app.soyoka.pro.monthly",
        original_transaction_id: "orig-tx-001",
      }),
    });

    expect(res.status).toBe(200);

    const body = (await res.json()) as {
      status: string;
      product_id: string;
      expires_at: string;
    };
    expect(body.status).toBe("active");
    expect(body.product_id).toBe("app.soyoka.pro.monthly");
    expect(body.expires_at).toBeDefined();

    // expires_at が未来の日付であること
    const expiresAt = new Date(body.expires_at);
    expect(expiresAt.getTime()).toBeGreaterThan(Date.now());

    // D1 のデバイスが pro に更新されていること
    const device = db._devices.get(DEVICE_ID);
    expect(device?.plan).toBe("pro");
    expect(device?.product_id).toBe("app.soyoka.pro.monthly");
    expect(device?.original_transaction_id).toBe("orig-tx-001");
  });

  it("認証なしで 401 を返却する", async () => {
    const res = await app.request("/api/v1/subscription/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        transaction_id: "tx-12345",
        product_id: "app.soyoka.pro.monthly",
        original_transaction_id: "orig-tx-001",
      }),
    });

    expect(res.status).toBe(401);

    const body = (await res.json()) as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("transaction_id 未指定で 400 を返却する", async () => {
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/subscription/verify", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({
        product_id: "app.soyoka.pro.monthly",
        original_transaction_id: "orig-tx-001",
      }),
    });

    expect(res.status).toBe(400);

    const body = (await res.json()) as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });
});

describe("POST /api/v1/subscription/webhook", () => {
  let app: Hono;
  let db: ReturnType<typeof createMockD1>;

  beforeEach(() => {
    const created = createApp();
    app = created.app;
    db = created.db;

    // Pro プランのデバイスを登録
    db._devices.set(DEVICE_ID, {
      id: DEVICE_ID,
      plan: "pro",
      product_id: "app.soyoka.pro.monthly",
      subscription_expires_at: "2026-04-28T00:00:00.000Z",
      original_transaction_id: "orig-tx-001",
    });
  });

  it("EXPIRED 通知で plan を free に更新する", async () => {
    const res = await app.request("/api/v1/subscription/webhook", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        notificationType: "EXPIRED",
        data: {
          originalTransactionId: "orig-tx-001",
        },
      }),
    });

    expect(res.status).toBe(200);

    const body = (await res.json()) as { status: string };
    expect(body.status).toBe("ok");

    // D1 のデバイスが free にダウングレードされていること
    const device = db._devices.get(DEVICE_ID);
    expect(device?.plan).toBe("free");
    expect(device?.subscription_expires_at).toBeNull();
  });

  it("REVOKE 通知で plan を free に更新する", async () => {
    const res = await app.request("/api/v1/subscription/webhook", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        notificationType: "REVOKE",
        data: {
          originalTransactionId: "orig-tx-001",
        },
      }),
    });

    expect(res.status).toBe(200);

    const body = (await res.json()) as { status: string };
    expect(body.status).toBe("ok");

    const device = db._devices.get(DEVICE_ID);
    expect(device?.plan).toBe("free");
  });

  it("その他の通知で 200 OK を返却し plan を変更しない", async () => {
    const res = await app.request("/api/v1/subscription/webhook", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        notificationType: "DID_RENEW",
        data: {
          originalTransactionId: "orig-tx-001",
        },
      }),
    });

    expect(res.status).toBe(200);

    // plan は pro のまま
    const device = db._devices.get(DEVICE_ID);
    expect(device?.plan).toBe("pro");
  });
});

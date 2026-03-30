import { Hono } from "hono";
import { SignJWT } from "jose";
import type { Env } from "../../src/types.js";

// --- Test JWT Generation ---

const TEST_JWT_SECRET = "test-secret-key-for-unit-tests-only";

/**
 * テスト用 JWT トークンを生成する
 */
export async function generateTestJwt(
  deviceId: string,
  options: {
    secret?: string;
    expiresIn?: string;
    plan?: string;
  } = {},
): Promise<string> {
  const secret = new TextEncoder().encode(options.secret ?? TEST_JWT_SECRET);
  const plan = options.plan ?? "free";

  return new SignJWT({ device_id: deviceId, plan })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime(options.expiresIn ?? "1h")
    .sign(secret);
}

// --- Mock Env ---

/**
 * テスト用の Env モックを生成する
 * D1 / KV は @cloudflare/vitest-pool-workers が提供するミニフレア環境を使用するため、
 * ここでは環境変数のみモックする
 */
export function createMockEnvVars(
  overrides: Partial<Omit<Env, "DB" | "KV">> = {},
): Omit<Env, "DB" | "KV"> {
  return {
    ENVIRONMENT: "test",
    OPENAI_API_KEY: "sk-test-dummy-key",
    JWT_SECRET: TEST_JWT_SECRET,
    ...overrides,
  };
}

// --- Test App Factory ---

/**
 * テスト用 Hono アプリを生成するファクトリ
 * env に D1 / KV を含む完全な Env を受け取ってアプリを構成する
 */
export function createTestApp(
  env: Env,
): Hono<{ Bindings: Env }> {
  const app = new Hono<{ Bindings: Env }>();

  // bindings を直接注入するミドルウェア
  app.use("*", async (c, next) => {
    Object.assign(c.env, env);
    await next();
  });

  return app;
}

// --- D1 Test Helpers ---

/**
 * テスト用デバイスレコードを D1 に挿入する
 */
export async function insertTestDevice(
  db: D1Database,
  device: {
    id: string;
    plan?: string;
    app_version?: string;
    os_version?: string;
  },
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO devices (id, plan, app_version, os_version)
       VALUES (?, ?, ?, ?)`,
    )
    .bind(
      device.id,
      device.plan ?? "free",
      device.app_version ?? "1.0.0",
      device.os_version ?? "18.0",
    )
    .run();
}

/**
 * テスト用デバイスレコードを D1 から取得する
 */
export async function getTestDevice(
  db: D1Database,
  deviceId: string,
): Promise<{
  id: string;
  plan: string;
  app_version: string | null;
  os_version: string | null;
  created_at: string;
  last_seen_at: string;
} | null> {
  const result = await db
    .prepare("SELECT * FROM devices WHERE id = ?")
    .bind(deviceId)
    .first<{
      id: string;
      plan: string;
      app_version: string | null;
      os_version: string | null;
      created_at: string;
      last_seen_at: string;
    }>();
  return result ?? null;
}

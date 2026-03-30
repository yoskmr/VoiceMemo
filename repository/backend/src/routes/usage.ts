import { Hono } from "hono";
import type { AuthEnv } from "../middleware/auth.js";
import { jwtAuthMiddleware } from "../middleware/auth.js";
import { getUsage, type Plan } from "../services/quota.js";

const usageRoutes = new Hono<AuthEnv>();

// JWT 認証ミドルウェアを全ルートに適用
usageRoutes.use("*", jwtAuthMiddleware);

// --- GET /api/v1/usage ---

usageRoutes.get("/", async (c) => {
  const deviceId = c.get("deviceId");

  // D1 からプラン情報取得
  const device = await c.env.DB.prepare(
    "SELECT plan FROM devices WHERE id = ?",
  )
    .bind(deviceId)
    .first<{ plan: string }>();

  const plan: Plan = device?.plan === "pro" ? "pro" : "free";

  // KV から使用量取得
  const usage = await getUsage(c.env.KV, deviceId, plan);

  return c.json({
    used: usage.used,
    limit: usage.limit,
    plan: usage.plan,
    resets_at: usage.resets_at,
  });
});

export { usageRoutes };

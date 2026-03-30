import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import type { Env } from "../types.js";
import { DeviceAuthRequestSchema } from "../types.js";
import { generateToken } from "../services/token.js";
import { createErrorResponse, ErrorCode } from "../errors.js";

const authRoutes = new Hono<{ Bindings: Env }>();

// --- POST /api/v1/auth/device ---

authRoutes.post(
  "/device",
  zValidator("json", DeviceAuthRequestSchema, (result, c) => {
    if (!result.success) {
      const requestId = crypto.randomUUID();
      const body = createErrorResponse(
        ErrorCode.INVALID_REQUEST,
        "Invalid request body",
        requestId,
        { issues: result.error.issues },
      );
      return c.json(body, 400);
    }
  }),
  async (c) => {
    const { device_id, app_version, os_version } = c.req.valid("json");

    // D1 に devices テーブルで upsert
    await c.env.DB.prepare(
      `INSERT INTO devices (id, app_version, os_version, last_seen_at)
       VALUES (?, ?, ?, datetime('now'))
       ON CONFLICT(id) DO UPDATE SET
         app_version = excluded.app_version,
         os_version = excluded.os_version,
         last_seen_at = datetime('now')`,
    )
      .bind(device_id, app_version, os_version)
      .run();

    // JWT 生成
    const { token, expiresAt } = await generateToken(device_id, c.env.JWT_SECRET);

    return c.json(
      {
        access_token: token,
        expires_at: expiresAt.toISOString(),
        device_id,
      },
      200,
    );
  },
);

export { authRoutes };

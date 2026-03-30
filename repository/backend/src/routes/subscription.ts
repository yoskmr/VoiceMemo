import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import type { Env } from "../types.js";
import { SubscriptionVerifyRequestSchema } from "../types.js";
import type { AuthEnv } from "../middleware/auth.js";
import { jwtAuthMiddleware } from "../middleware/auth.js";
import { createErrorResponse, ErrorCode } from "../errors.js";

const subscriptionRoutes = new Hono<AuthEnv>();

// --- POST /api/v1/subscription/verify (認証必須) ---

subscriptionRoutes.post(
  "/verify",
  jwtAuthMiddleware,
  zValidator("json", SubscriptionVerifyRequestSchema, (result, c) => {
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
    const deviceId = c.get("deviceId");
    const { transaction_id, product_id, original_transaction_id } =
      c.req.valid("json");

    // 30日後の有効期限（MVP: 固定30日）
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);
    const expiresAtISO = expiresAt.toISOString();

    // D1: devices テーブルの plan を 'pro' に更新、サブスクリプション情報を保存
    await c.env.DB.prepare(
      `UPDATE devices
       SET plan = 'pro',
           product_id = ?,
           subscription_expires_at = ?,
           original_transaction_id = ?
       WHERE id = ?`,
    )
      .bind(product_id, expiresAtISO, original_transaction_id, deviceId)
      .run();

    console.info(
      JSON.stringify({
        event: "subscription_verified",
        device_id: deviceId,
        product_id,
        transaction_id,
        expires_at: expiresAtISO,
      }),
    );

    return c.json({
      status: "active",
      product_id,
      expires_at: expiresAtISO,
    });
  },
);

// --- POST /api/v1/subscription/webhook (認証不要 — Apple からの通知) ---

subscriptionRoutes.post("/webhook", async (c) => {
  const body = await c.req.json<{
    notificationType?: string;
    data?: {
      signedTransactionInfo?: string;
      originalTransactionId?: string;
    };
  }>();

  const notificationType = body.notificationType ?? "UNKNOWN";

  console.info(
    JSON.stringify({
      event: "webhook_received",
      notification_type: notificationType,
    }),
  );

  // EXPIRED / REVOKE の場合: plan を 'free' に戻す
  if (notificationType === "EXPIRED" || notificationType === "REVOKE") {
    const originalTransactionId = body.data?.originalTransactionId;

    if (originalTransactionId) {
      await c.env.DB.prepare(
        `UPDATE devices
         SET plan = 'free',
             subscription_expires_at = NULL
         WHERE original_transaction_id = ?`,
      )
        .bind(originalTransactionId)
        .run();

      console.info(
        JSON.stringify({
          event: "subscription_downgraded",
          notification_type: notificationType,
          original_transaction_id: originalTransactionId,
        }),
      );
    }
  }

  return c.json({ status: "ok" }, 200);
});

export { subscriptionRoutes };

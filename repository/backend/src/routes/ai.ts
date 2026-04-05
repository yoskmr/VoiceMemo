import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { AIProcessRequestSchema, AIChatRequestSchema, AIPolishRequestSchema } from "../types.js";
import type { AuthEnv } from "../middleware/auth.js";
import { jwtAuthMiddleware } from "../middleware/auth.js";
import { createErrorResponse, ErrorCode, createHttpException } from "../errors.js";
import { processAI, processChat, processPolish, OpenAIError, getModelName } from "../services/openai.js";
import { checkQuota, incrementUsage, getUsage, type Plan } from "../services/quota.js";

const aiRoutes = new Hono<AuthEnv>();

// JWT 認証ミドルウェアを全ルートに適用
aiRoutes.use("*", jwtAuthMiddleware);

// --- POST /api/v1/ai/process ---

aiRoutes.post(
  "/process",
  zValidator("json", AIProcessRequestSchema, (result, c) => {
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
    const requestId = crypto.randomUUID();
    const startTime = Date.now();
    const deviceId = c.get("deviceId");
    const { text, language, options, context } = c.req.valid("json");

    // D1 からデバイス情報取得（plan 判定）
    const device = await c.env.DB.prepare(
      "SELECT plan FROM devices WHERE id = ?",
    )
      .bind(deviceId)
      .first<{ plan: string }>();

    const plan: Plan = device?.plan === "pro" ? "pro" : "free";

    // 無料プラン: 月次上限チェック
    const canProceed = await checkQuota(c.env.KV, deviceId, plan);
    if (!canProceed) {
      const usage = await getUsage(c.env.KV, deviceId, plan);
      throw createHttpException(
        ErrorCode.USAGE_LIMIT_EXCEEDED,
        "Monthly usage limit exceeded",
        requestId,
        {
          used: usage.used,
          limit: usage.limit,
          resets_at: usage.resets_at,
        },
      );
    }

    // OpenAI API 呼び出し
    let aiResult;
    try {
      aiResult = await processAI(
        { text, language, options, context },
        c.env.OPENAI_API_KEY,
      );
    } catch (error) {
      if (error instanceof OpenAIError) {
        const code = error.isUpstream ? ErrorCode.UPSTREAM_ERROR : ErrorCode.INTERNAL_ERROR;
        const status = error.isUpstream ? 502 : 500;
        // テキストデータをログに含めない（request_id, device_id, processing_time_ms のみ）
        console.error(JSON.stringify({
          request_id: requestId,
          device_id: deviceId,
          processing_time_ms: Date.now() - startTime,
          error: error.message,
        }));
        throw createHttpException(code, error.message, requestId);
      }
      throw error;
    }

    // 使用量インクリメント
    await incrementUsage(c.env.KV, deviceId);

    // 最新の使用量情報取得
    const usage = await getUsage(c.env.KV, deviceId, plan);

    const processingTimeMs = Date.now() - startTime;

    // テキストデータをログに含めない
    console.info(JSON.stringify({
      request_id: requestId,
      device_id: deviceId,
      processing_time_ms: processingTimeMs,
    }));

    return c.json({
      summary: aiResult.summary,
      tags: aiResult.tags,
      sentiment: aiResult.sentiment,
      usage: {
        used: usage.used,
        limit: usage.limit,
        plan: usage.plan,
        resets_at: usage.resets_at,
      },
      metadata: {
        model: getModelName(),
        provider: "cloud_gpt4o_mini",
        processing_time_ms: processingTimeMs,
        request_id: requestId,
      },
    });
  },
);

// --- POST /api/v1/ai/chat (きおくに聞く) ---

aiRoutes.post(
  "/chat",
  zValidator("json", AIChatRequestSchema, (result, c) => {
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
    const requestId = crypto.randomUUID();
    const startTime = Date.now();
    const deviceId = c.get("deviceId");
    const { question, context_memos, language } = c.req.valid("json");

    // D1 からデバイス情報取得（Pro プラン確認）
    const device = await c.env.DB.prepare(
      "SELECT plan FROM devices WHERE id = ?",
    )
      .bind(deviceId)
      .first<{ plan: string }>();

    if (!device || device.plan !== "pro") {
      throw createHttpException(
        ErrorCode.FORBIDDEN,
        "This feature requires a Pro plan",
        requestId,
      );
    }

    // OpenAI API 呼び出し
    let chatResult;
    try {
      chatResult = await processChat(
        { question, contextMemos: context_memos, language },
        c.env.OPENAI_API_KEY,
      );
    } catch (error) {
      if (error instanceof OpenAIError) {
        const code = error.isUpstream ? ErrorCode.UPSTREAM_ERROR : ErrorCode.INTERNAL_ERROR;
        console.error(JSON.stringify({
          request_id: requestId,
          device_id: deviceId,
          processing_time_ms: Date.now() - startTime,
          error: error.message,
        }));
        throw createHttpException(code, error.message, requestId);
      }
      throw error;
    }

    const processingTimeMs = Date.now() - startTime;

    console.info(JSON.stringify({
      request_id: requestId,
      device_id: deviceId,
      processing_time_ms: processingTimeMs,
    }));

    return c.json({
      answer: chatResult.answer,
      referenced_memo_ids: chatResult.referenced_memo_ids,
      metadata: {
        model: getModelName(),
        processing_time_ms: processingTimeMs,
        request_id: requestId,
        provider: "openai",
      },
    });
  },
);

// --- POST /api/v1/ai/polish (高精度仕上げ) ---

aiRoutes.post(
  "/polish",
  zValidator("json", AIPolishRequestSchema, (result, c) => {
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
    const requestId = crypto.randomUUID();
    const startTime = Date.now();
    const deviceId = c.get("deviceId");
    const { text, custom_dictionary, language } = c.req.valid("json");

    // D1 からデバイス情報取得（Pro プラン確認）
    const device = await c.env.DB.prepare(
      "SELECT plan FROM devices WHERE id = ?",
    )
      .bind(deviceId)
      .first<{ plan: string }>();

    if (!device || device.plan !== "pro") {
      throw createHttpException(
        ErrorCode.FORBIDDEN,
        "This feature requires a Pro plan",
        requestId,
      );
    }

    // OpenAI API 呼び出し
    let polishResult;
    try {
      polishResult = await processPolish(
        { text, customDictionary: custom_dictionary, language },
        c.env.OPENAI_API_KEY,
      );
    } catch (error) {
      if (error instanceof OpenAIError) {
        const code = error.isUpstream ? ErrorCode.UPSTREAM_ERROR : ErrorCode.INTERNAL_ERROR;
        console.error(JSON.stringify({
          request_id: requestId,
          device_id: deviceId,
          processing_time_ms: Date.now() - startTime,
          error: error.message,
        }));
        throw createHttpException(code, error.message, requestId);
      }
      throw error;
    }

    const processingTimeMs = Date.now() - startTime;

    console.info(JSON.stringify({
      request_id: requestId,
      device_id: deviceId,
      processing_time_ms: processingTimeMs,
    }));

    return c.json({
      polished_text: polishResult.polished_text,
      metadata: {
        model: getModelName(),
        processing_time_ms: processingTimeMs,
        request_id: requestId,
        provider: "openai",
      },
    });
  },
);

export { aiRoutes };

import type { MiddlewareHandler } from "hono";
import type { Env } from "../types.js";

// --- Request ID Variables type ---

type RequestIdVariables = {
  requestId: string;
};

export type RequestIdEnv = {
  Bindings: Env;
  Variables: RequestIdVariables;
};

// --- Request ID Middleware ---

/**
 * リクエスト ID ミドルウェア
 * X-Request-ID ヘッダーがあればそのまま使用し、なければ crypto.randomUUID() で生成する。
 * レスポンスヘッダーにも X-Request-ID を付与する。
 */
export const requestIdMiddleware: MiddlewareHandler<RequestIdEnv> = async (c, next) => {
  const existingId = c.req.header("X-Request-ID");
  const requestId = existingId ?? crypto.randomUUID();

  c.set("requestId", requestId);

  await next();

  c.header("X-Request-ID", requestId);
};

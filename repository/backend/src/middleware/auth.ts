import type { MiddlewareHandler } from "hono";
import type { Env } from "../types.js";
import { verifyToken } from "../services/token.js";
import { createErrorResponse, ErrorCode } from "../errors.js";

// --- Variables type for Hono context ---

type AuthVariables = {
  deviceId: string;
};

export type AuthEnv = {
  Bindings: Env;
  Variables: AuthVariables;
};

// --- JWT Authentication Middleware ---

/**
 * Authorization: Bearer <token> ヘッダーから JWT を検証し、
 * 成功時は c.set('deviceId', deviceId) でコンテキストに格納する。
 * 失敗時は 401 UNAUTHORIZED を返す。
 */
export const jwtAuthMiddleware: MiddlewareHandler<AuthEnv> = async (c, next) => {
  const authHeader = c.req.header("Authorization");

  if (authHeader === undefined || !authHeader.startsWith("Bearer ")) {
    const requestId = crypto.randomUUID();
    const body = createErrorResponse(
      ErrorCode.UNAUTHORIZED,
      "Missing or invalid Authorization header",
      requestId,
    );
    return c.json(body, 401);
  }

  const token = authHeader.slice(7); // "Bearer ".length === 7

  try {
    const { deviceId } = await verifyToken(token, c.env.JWT_SECRET);
    c.set("deviceId", deviceId);
    await next();
  } catch {
    const requestId = crypto.randomUUID();
    const body = createErrorResponse(
      ErrorCode.UNAUTHORIZED,
      "Invalid or expired token",
      requestId,
    );
    return c.json(body, 401);
  }
};

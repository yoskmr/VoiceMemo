import { HTTPException } from "hono/http-exception";
import type { ErrorResponse } from "./types.js";

// --- Error Code Constants ---

export const ErrorCode = {
  INVALID_REQUEST: "INVALID_REQUEST",
  UNAUTHORIZED: "UNAUTHORIZED",
  FORBIDDEN: "FORBIDDEN",
  RATE_LIMITED: "RATE_LIMITED",
  USAGE_LIMIT_EXCEEDED: "USAGE_LIMIT_EXCEEDED",
  INTERNAL_ERROR: "INTERNAL_ERROR",
  UPSTREAM_ERROR: "UPSTREAM_ERROR",
} as const;

export type ErrorCodeType = (typeof ErrorCode)[keyof typeof ErrorCode];

const errorStatusMap: Record<ErrorCodeType, number> = {
  [ErrorCode.INVALID_REQUEST]: 400,
  [ErrorCode.UNAUTHORIZED]: 401,
  [ErrorCode.FORBIDDEN]: 403,
  [ErrorCode.RATE_LIMITED]: 429,
  [ErrorCode.USAGE_LIMIT_EXCEEDED]: 429,
  [ErrorCode.INTERNAL_ERROR]: 500,
  [ErrorCode.UPSTREAM_ERROR]: 502,
};

// --- Error Response Builder ---

export function createErrorResponse(
  code: ErrorCodeType,
  message: string,
  requestId: string,
  details?: Record<string, unknown>,
): ErrorResponse {
  return {
    error: {
      code,
      message,
      ...(details !== undefined ? { details } : {}),
      request_id: requestId,
    },
  };
}

// --- HTTP Exception Factory ---

export function createHttpException(
  code: ErrorCodeType,
  message: string,
  requestId: string,
  details?: Record<string, unknown>,
): HTTPException {
  const status = errorStatusMap[code] as
    | 400
    | 401
    | 403
    | 429
    | 500
    | 502;
  const body = JSON.stringify(createErrorResponse(code, message, requestId, details));
  return new HTTPException(status, {
    message,
    res: new Response(body, {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  });
}

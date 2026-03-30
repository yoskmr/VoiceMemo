import type { MiddlewareHandler } from "hono";
import type { Env } from "../types.js";
import { createErrorResponse, ErrorCode } from "../errors.js";

// --- Constants ---

const WINDOW_SECONDS = 60;
const KV_TTL_SECONDS = 120; // ウィンドウの2倍（安全マージン）

// --- Rate Limit Config ---

export interface RateLimitConfig {
  /** 1分間あたりの最大リクエスト数 */
  maxRequests: number;
}

// --- KV Key Generation ---

function getRateLimitKey(ip: string, windowId: number): string {
  return `ratelimit:${ip}:${windowId}`;
}

function getCurrentWindow(): number {
  return Math.floor(Date.now() / 1000 / WINDOW_SECONDS);
}

// --- Rate Limit Middleware Factory ---

/**
 * KV ベースのスライディングウィンドウ型レート制限ミドルウェア
 * KV キー: `ratelimit:{ip}:{window}` (60秒ウィンドウ)
 * 超過時: 429 RATE_LIMITED
 */
export function createRateLimitMiddleware(
  config: RateLimitConfig,
): MiddlewareHandler<{ Bindings: Env }> {
  return async (c, next) => {
    const ip = c.req.header("CF-Connecting-IP")
      ?? c.req.header("X-Forwarded-For")?.split(",")[0]?.trim()
      ?? "unknown";

    const window = getCurrentWindow();
    const key = getRateLimitKey(ip, window);

    const currentStr = await c.env.KV.get(key);
    const current = currentStr !== null ? parseInt(currentStr, 10) : 0;

    if (current >= config.maxRequests) {
      const requestId = crypto.randomUUID();
      const body = createErrorResponse(
        ErrorCode.RATE_LIMITED,
        "Too many requests",
        requestId,
        {
          limit: config.maxRequests,
          window_seconds: WINDOW_SECONDS,
          retry_after: WINDOW_SECONDS,
        },
      );
      c.header("Retry-After", String(WINDOW_SECONDS));
      return c.json(body, 429);
    }

    // カウントを +1
    const newCount = current + 1;
    await c.env.KV.put(key, String(newCount), { expirationTtl: KV_TTL_SECONDS });

    // レスポンスヘッダーにレート制限情報を付与
    c.header("X-RateLimit-Limit", String(config.maxRequests));
    c.header("X-RateLimit-Remaining", String(Math.max(0, config.maxRequests - newCount)));

    await next();
  };
}

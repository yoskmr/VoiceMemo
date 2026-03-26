import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import type { Env } from "./types.js";
import { createErrorResponse, ErrorCode } from "./errors.js";
import { authRoutes } from "./routes/auth.js";
import { aiRoutes } from "./routes/ai.js";
import { usageRoutes } from "./routes/usage.js";
import { requestIdMiddleware } from "./middleware/requestId.js";
import { createRateLimitMiddleware } from "./middleware/rateLimit.js";

const app = new Hono<{ Bindings: Env }>();

// --- Global Middleware: Request ID ---

app.use("*", requestIdMiddleware);

// --- Health Check (認証不要、レート制限なし) ---

app.get("/health", (c) => {
  return c.json({
    status: "ok",
    environment: c.env.ENVIRONMENT ?? "unknown",
  });
});

// --- Auth Routes (認証不要、レート制限あり: 120/min) ---

app.use("/api/v1/auth/*", createRateLimitMiddleware({ maxRequests: 120 }));
app.route("/api/v1/auth", authRoutes);

// --- AI Routes (認証必須、レート制限あり: 60/min) ---

app.use("/api/v1/ai/*", createRateLimitMiddleware({ maxRequests: 60 }));
app.route("/api/v1/ai", aiRoutes);

// --- Usage Routes (認証必須、レート制限あり: 120/min) ---

app.use("/api/v1/usage", createRateLimitMiddleware({ maxRequests: 120 }));
app.use("/api/v1/usage/*", createRateLimitMiddleware({ maxRequests: 120 }));
app.route("/api/v1/usage", usageRoutes);

// --- Error Handler ---

app.onError((err, c) => {
  if (err instanceof HTTPException && err.res !== undefined) {
    return err.res;
  }

  const requestId = crypto.randomUUID();
  const body = createErrorResponse(
    ErrorCode.INTERNAL_ERROR,
    "An unexpected error occurred",
    requestId,
  );
  return c.json(body, 500);
});

// --- Not Found Handler ---

app.notFound((c) => {
  const requestId = crypto.randomUUID();
  const body = createErrorResponse(
    ErrorCode.INVALID_REQUEST,
    `Route not found: ${c.req.method} ${c.req.path}`,
    requestId,
  );
  return c.json(body, 404);
});

export default app;

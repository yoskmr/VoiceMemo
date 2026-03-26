import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import type { Env } from "./types.js";
import { createErrorResponse, ErrorCode } from "./errors.js";
import { authRoutes } from "./routes/auth.js";

const app = new Hono<{ Bindings: Env }>();

// --- Health Check (認証不要) ---

app.get("/health", (c) => {
  return c.json({
    status: "ok",
    environment: c.env.ENVIRONMENT ?? "unknown",
  });
});

// --- Auth Routes (認証不要) ---

app.route("/api/v1/auth", authRoutes);

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

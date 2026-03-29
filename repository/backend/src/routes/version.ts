import { Hono } from "hono";
import type { Env } from "../types.js";

const versionRoutes = new Hono<{ Bindings: Env }>();

versionRoutes.get("/check", async (c) => {
  const minimumVersion =
    (await c.env.KV.get("minimum_app_version")) ?? "1.0.0";
  const storeUrl = (await c.env.KV.get("app_store_url")) ?? "";

  return c.json({
    minimum_version: minimumVersion,
    store_url: storeUrl,
  });
});

export { versionRoutes };

import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import type { Env } from "../../src/types.js";
import { promptRoutes } from "../../src/routes/prompts.js";

function createApp(): Hono<{ Bindings: Env }> {
  const app = new Hono<{ Bindings: Env }>();

  app.use("*", async (c, next) => {
    c.env = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: "test-secret",
      DB: {} as D1Database,
      KV: {} as KVNamespace,
    } as Env;
    await next();
  });

  app.route("/api/v1/prompts", promptRoutes);

  return app;
}

describe("GET /api/v1/prompts/latest", () => {
  it("正常系: プロンプトテンプレートを返却する", async () => {
    const app = createApp();

    const res = await app.request("/api/v1/prompts/latest", {
      method: "GET",
    });

    expect(res.status).toBe(200);

    const body = (await res.json()) as {
      version: string;
      updatedAt: string;
      templates: Record<string, string>;
      basePrompt: string;
    };

    expect(body.version).toBe("3.1.0");
    expect(body.updatedAt).toBeDefined();
    expect(body.templates).toBeDefined();
    expect(body.templates.soft).toBe("");
    expect(body.templates.formal).toContain("きちんと");
    expect(body.templates.casual).toContain("ひとりごと");
    expect(body.templates.reflection).toContain("ふりかえり");
    expect(body.templates.essay).toContain("エッセイ");
    expect(body.basePrompt).toContain("音声メモの文字起こし");
  });

  it("認証なしでもアクセスできる", async () => {
    const app = createApp();

    const res = await app.request("/api/v1/prompts/latest", {
      method: "GET",
    });

    // 認証不要なので 200 を返す
    expect(res.status).toBe(200);
  });
});

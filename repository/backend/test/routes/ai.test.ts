import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { Hono } from "hono";
import type { Env } from "../../src/types.js";
import { aiRoutes } from "../../src/routes/ai.js";
import { generateToken } from "../../src/services/token.js";

// --- Mock Data ---

const VALID_AI_RESPONSE = {
  summary: {
    title: "テスト要約",
    brief: "これはテストの要約です",
    key_points: ["要点1", "要点2"],
  },
  tags: [
    { label: "テスト", confidence: 0.95 },
    { label: "サンプル", confidence: 0.80 },
  ],
  sentiment: {
    primary: "joy",
    scores: {
      joy: 0.6,
      sadness: 0.05,
      anger: 0.0,
      fear: 0.0,
      surprise: 0.1,
      disgust: 0.0,
      anticipation: 0.15,
      trust: 0.1,
    },
    evidence: ["嬉しいテキスト"],
  },
};

function createMockOpenAIFetchResponse(content: unknown): Response {
  return new Response(
    JSON.stringify({
      id: "chatcmpl-test",
      object: "chat.completion",
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: JSON.stringify(content),
          },
          finish_reason: "stop",
        },
      ],
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}

// --- D1 Mock ---

interface MockDevice {
  id: string;
  plan: string;
}

function createMockD1(devices: MockDevice[] = []): D1Database {
  const deviceMap = new Map(devices.map((d) => [d.id, d]));

  const mockD1 = {
    prepare: (sql: string) => {
      let boundValues: unknown[] = [];
      return {
        bind: (...values: unknown[]) => {
          boundValues = values;
          return {
            run: async () => ({ success: true, results: [], meta: {} }),
            first: async () => {
              if (sql.includes("SELECT plan FROM devices")) {
                const [id] = boundValues as [string];
                const device = deviceMap.get(id);
                return device ? { plan: device.plan } : null;
              }
              return null;
            },
          };
        },
        run: async () => ({ success: true, results: [], meta: {} }),
        first: async () => null,
      };
    },
    dump: async () => new ArrayBuffer(0),
    batch: async () => [],
    exec: async () => ({ count: 0, duration: 0 }),
  } as unknown as D1Database;

  return mockD1;
}

// --- KV Mock ---

function createMockKV(): KVNamespace & { _store: Map<string, { value: string; ttl?: number }> } {
  const store = new Map<string, { value: string; ttl?: number }>();

  return {
    _store: store,
    get: async (key: string) => {
      const entry = store.get(key);
      return entry?.value ?? null;
    },
    put: async (key: string, value: string, options?: { expirationTtl?: number }) => {
      store.set(key, { value, ttl: options?.expirationTtl });
    },
    delete: async (key: string) => {
      store.delete(key);
    },
    list: async () => ({ keys: [], list_complete: true, cacheStatus: null }),
    getWithMetadata: async (key: string) => {
      const entry = store.get(key);
      return { value: entry?.value ?? null, metadata: null, cacheStatus: null };
    },
  } as unknown as KVNamespace & { _store: Map<string, { value: string; ttl?: number }> };
}

// --- Test Constants ---

const TEST_SECRET = "test-secret-key-for-unit-tests-only";
const DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000";

// --- Test Setup ---

interface AppOptions {
  devices?: MockDevice[];
  kv?: ReturnType<typeof createMockKV>;
}

function createApp(options: AppOptions = {}): Hono<{ Bindings: Env }> {
  const app = new Hono<{ Bindings: Env }>();

  const devices = options.devices ?? [{ id: DEVICE_ID, plan: "free" }];
  const kv = options.kv ?? createMockKV();

  app.use("*", async (c, next) => {
    c.env = {
      ENVIRONMENT: "test",
      OPENAI_API_KEY: "sk-test",
      JWT_SECRET: TEST_SECRET,
      DB: createMockD1(devices),
      KV: kv,
    } as Env;
    await next();
  });

  app.route("/api/v1/ai", aiRoutes);

  return app;
}

async function getAuthHeader(): Promise<string> {
  const { token } = await generateToken(DEVICE_ID, TEST_SECRET);
  return `Bearer ${token}`;
}

const VALID_REQUEST_BODY = {
  text: "今日はとても良い天気で気分が良いです。",
  language: "ja",
};

// --- Tests ---

describe("POST /api/v1/ai/process", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("正常系: 全フィールドを返却する", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      createMockOpenAIFetchResponse(VALID_AI_RESPONSE),
    );

    const app = createApp();
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_REQUEST_BODY),
    });

    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, unknown>;

    // AI 結果
    expect(body.summary).toBeDefined();
    expect(body.tags).toBeDefined();
    expect(body.sentiment).toBeDefined();

    // 使用量
    const usage = body.usage as Record<string, unknown>;
    expect(usage.used).toBe(1);
    expect(usage.limit).toBe(10);
    expect(usage.plan).toBe("free");
    expect(usage.resets_at).toBeDefined();

    // メタデータ
    const metadata = body.metadata as Record<string, unknown>;
    expect(metadata.model).toBe("gpt-4o-mini");
    expect(metadata.provider).toBe("cloud_gpt4o_mini");
    expect(metadata.processing_time_ms).toBeDefined();
    expect(metadata.request_id).toBeDefined();
  });

  it("認証なしで 401 を返却する", async () => {
    const app = createApp();

    const res = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(VALID_REQUEST_BODY),
    });

    expect(res.status).toBe(401);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("テキスト未入力で 400 を返却する", async () => {
    const app = createApp();
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({ language: "ja" }),
    });

    expect(res.status).toBe(400);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });

  it("空文字テキストで 400 を返却する", async () => {
    const app = createApp();
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({ text: "", language: "ja" }),
    });

    expect(res.status).toBe(400);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });

  it("月次上限到達で 429 USAGE_LIMIT_EXCEEDED を返却する", async () => {
    const kv = createMockKV();

    // 10回分使用済みにする
    const yearMonth = (() => {
      const now = new Date();
      const year = now.getUTCFullYear();
      const month = String(now.getUTCMonth() + 1).padStart(2, "0");
      return `${year}-${month}`;
    })();
    kv._store.set(`usage:${DEVICE_ID}:${yearMonth}`, { value: "10" });

    const app = createApp({ kv });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_REQUEST_BODY),
    });

    expect(res.status).toBe(429);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("USAGE_LIMIT_EXCEEDED");
  });

  it("OpenAI エラーで 502 を返却する", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { message: "API error" } }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const app = createApp();
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_REQUEST_BODY),
    });

    expect(res.status).toBe(502);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("UPSTREAM_ERROR");
  });

  it("処理成功後に使用量がインクリメントされる", async () => {
    globalThis.fetch = vi.fn().mockImplementation(() =>
      Promise.resolve(createMockOpenAIFetchResponse(VALID_AI_RESPONSE)),
    );

    const kv = createMockKV();
    const app = createApp({ kv });
    const auth = await getAuthHeader();

    // 1回目
    const res1 = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_REQUEST_BODY),
    });

    expect(res1.status).toBe(200);
    const body1 = await res1.json() as { usage: { used: number } };
    expect(body1.usage.used).toBe(1);

    // 2回目
    const res2 = await app.request("/api/v1/ai/process", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_REQUEST_BODY),
    });

    expect(res2.status).toBe(200);
    const body2 = await res2.json() as { usage: { used: number } };
    expect(body2.usage.used).toBe(2);
  });
});

// --- Chat / Polish Mock Data ---

const VALID_CHAT_RESPONSE = {
  answer: "お天気が良い日が多かったようですね。[きおく1]で記録されています。",
  referenced_memo_ids: ["memo-1"],
};

const VALID_POLISH_RESPONSE = {
  polished_text: "今日はとても良い天気で、気分が良いです。",
};

const VALID_CHAT_REQUEST_BODY = {
  question: "最近の天気はどうだった？",
  context_memos: [
    {
      id: "memo-1",
      title: "天気メモ",
      text: "今日はとても良い天気で気分が良いです。",
      date: "2026-04-01",
      emotion: "joy",
      tags: ["天気", "日常"],
    },
  ],
  language: "ja",
};

const VALID_POLISH_REQUEST_BODY = {
  text: "えーと今日はあのーとても良い天気でまあ気分が良いです。",
  language: "ja",
};

// --- POST /api/v1/ai/chat Tests ---

describe("POST /api/v1/ai/chat", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("Pro ユーザーが質問応答を取得できる", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      createMockOpenAIFetchResponse(VALID_CHAT_RESPONSE),
    );

    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "pro" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_CHAT_REQUEST_BODY),
    });

    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, unknown>;

    expect(body.answer).toBeDefined();
    expect(body.referenced_memo_ids).toBeDefined();

    const metadata = body.metadata as Record<string, unknown>;
    expect(metadata.model).toBe("gpt-4o-mini");
    expect(metadata.provider).toBe("openai");
    expect(metadata.processing_time_ms).toBeDefined();
    expect(metadata.request_id).toBeDefined();
  });

  it("Free ユーザーは 403 FORBIDDEN を受ける", async () => {
    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "free" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_CHAT_REQUEST_BODY),
    });

    expect(res.status).toBe(403);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("FORBIDDEN");
  });

  it("context_memos が空の場合 400 エラー", async () => {
    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "pro" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({
        question: "テスト質問",
        context_memos: [],
        language: "ja",
      }),
    });

    expect(res.status).toBe(400);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });

  it("question が空の場合 400 エラー", async () => {
    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "pro" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({
        question: "",
        context_memos: VALID_CHAT_REQUEST_BODY.context_memos,
        language: "ja",
      }),
    });

    expect(res.status).toBe(400);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });
});

// --- POST /api/v1/ai/polish Tests ---

describe("POST /api/v1/ai/polish", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("Pro ユーザーが仕上げテキストを取得できる", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      createMockOpenAIFetchResponse(VALID_POLISH_RESPONSE),
    );

    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "pro" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/polish", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_POLISH_REQUEST_BODY),
    });

    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, unknown>;

    expect(body.polished_text).toBeDefined();

    const metadata = body.metadata as Record<string, unknown>;
    expect(metadata.model).toBe("gpt-4o-mini");
    expect(metadata.provider).toBe("openai");
    expect(metadata.processing_time_ms).toBeDefined();
    expect(metadata.request_id).toBeDefined();
  });

  it("Free ユーザーは 403 FORBIDDEN を受ける", async () => {
    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "free" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/polish", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(VALID_POLISH_REQUEST_BODY),
    });

    expect(res.status).toBe(403);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("FORBIDDEN");
  });

  it("custom_dictionary が渡された場合もプロンプトに含まれる", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      createMockOpenAIFetchResponse(VALID_POLISH_RESPONSE),
    );

    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "pro" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/polish", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({
        ...VALID_POLISH_REQUEST_BODY,
        custom_dictionary: [
          { reading: "そよか", display: "Soyoka" },
        ],
      }),
    });

    expect(res.status).toBe(200);

    const body = await res.json() as Record<string, unknown>;
    expect(body.polished_text).toBeDefined();

    // fetch が呼ばれたことを確認し、プロンプトにカスタム辞書が含まれる
    const fetchCall = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    const requestBody = JSON.parse(fetchCall[1].body as string);
    const systemContent = requestBody.messages[0].content as string;
    expect(systemContent).toContain("そよか");
    expect(systemContent).toContain("Soyoka");
  });

  it("text が空の場合 400 エラー", async () => {
    const app = createApp({
      devices: [{ id: DEVICE_ID, plan: "pro" }],
    });
    const auth = await getAuthHeader();

    const res = await app.request("/api/v1/ai/polish", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({ text: "", language: "ja" }),
    });

    expect(res.status).toBe(400);

    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe("INVALID_REQUEST");
  });
});

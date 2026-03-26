import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { processAI, OpenAIError, type ProcessAIParams } from "../../src/services/openai.js";

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
    primary: "joy" as const,
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

function createMockOpenAIResponse(content: unknown): Response {
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

const DEFAULT_PARAMS: ProcessAIParams = {
  text: "今日はとても良い天気で、気分が良いです。",
  language: "ja",
};

const API_KEY = "sk-test-key";

// --- Tests ---

describe("openai service", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  describe("processAI", () => {
    it("正常系: OpenAI レスポンスをパースして返却する", async () => {
      globalThis.fetch = vi.fn().mockResolvedValue(
        createMockOpenAIResponse(VALID_AI_RESPONSE),
      );

      const result = await processAI(DEFAULT_PARAMS, API_KEY);

      expect(result.summary).toBeDefined();
      expect(result.summary!.title).toBe("テスト要約");
      expect(result.summary!.brief).toBe("これはテストの要約です");
      expect(result.summary!.key_points).toEqual(["要点1", "要点2"]);
      expect(result.tags).toHaveLength(2);
      expect(result.sentiment!.primary).toBe("joy");
      expect(result.sentiment!.scores.joy).toBe(0.6);

      // fetch が正しいパラメータで呼ばれたことを確認
      expect(globalThis.fetch).toHaveBeenCalledTimes(1);
      const callArgs = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]!;
      expect(callArgs[0]).toBe("https://api.openai.com/v1/chat/completions");
      const body = JSON.parse(callArgs[1].body);
      expect(body.model).toBe("gpt-4o-mini");
      expect(body.temperature).toBe(0.3);
      expect(body.response_format).toEqual({ type: "json_object" });
    });

    it("options で summary=false の場合、null summary を正しくパースする", async () => {
      const responseWithNullSummary = {
        ...VALID_AI_RESPONSE,
        summary: null,
      };

      globalThis.fetch = vi.fn().mockResolvedValue(
        createMockOpenAIResponse(responseWithNullSummary),
      );

      const result = await processAI(
        { ...DEFAULT_PARAMS, options: { summary: false } },
        API_KEY,
      );

      expect(result.summary).toBeNull();
      expect(result.tags).toHaveLength(2);
      expect(result.sentiment).toBeDefined();
    });

    it("OpenAI API エラー（非 2xx）で 502 OpenAIError をスローする", async () => {
      globalThis.fetch = vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: { message: "Rate limit exceeded" } }), {
          status: 429,
          headers: { "Content-Type": "application/json" },
        }),
      );

      await expect(processAI(DEFAULT_PARAMS, API_KEY)).rejects.toThrow(OpenAIError);

      try {
        await processAI(DEFAULT_PARAMS, API_KEY);
      } catch (error) {
        expect(error).toBeInstanceOf(OpenAIError);
        expect((error as OpenAIError).statusCode).toBe(502);
        expect((error as OpenAIError).isUpstream).toBe(true);
      }
    });

    it("ネットワークエラーで 502 OpenAIError をスローする", async () => {
      globalThis.fetch = vi.fn().mockRejectedValue(new Error("Network error"));

      await expect(processAI(DEFAULT_PARAMS, API_KEY)).rejects.toThrow(OpenAIError);

      try {
        await processAI(DEFAULT_PARAMS, API_KEY);
      } catch (error) {
        expect(error).toBeInstanceOf(OpenAIError);
        expect((error as OpenAIError).statusCode).toBe(502);
        expect((error as OpenAIError).isUpstream).toBe(true);
      }
    });

    it("JSON パース失敗（不正な content）で 500 OpenAIError をスローする", async () => {
      // content が有効な JSON でない場合
      globalThis.fetch = vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            choices: [
              {
                message: {
                  role: "assistant",
                  content: "This is not valid JSON",
                },
              },
            ],
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );

      await expect(processAI(DEFAULT_PARAMS, API_KEY)).rejects.toThrow(OpenAIError);

      try {
        await processAI(DEFAULT_PARAMS, API_KEY);
      } catch (error) {
        expect(error).toBeInstanceOf(OpenAIError);
        expect((error as OpenAIError).statusCode).toBe(500);
        expect((error as OpenAIError).isUpstream).toBe(false);
      }
    });

    it("Zod バリデーション失敗で 500 OpenAIError をスローする", async () => {
      // 不正な構造（primary が不正な値）
      const invalidResponse = {
        summary: { title: "Test", brief: "Test", key_points: [] },
        tags: [],
        sentiment: {
          primary: "invalid_emotion",
          scores: {},
          evidence: [],
        },
      };

      globalThis.fetch = vi.fn().mockResolvedValue(
        createMockOpenAIResponse(invalidResponse),
      );

      await expect(processAI(DEFAULT_PARAMS, API_KEY)).rejects.toThrow(OpenAIError);

      try {
        await processAI(DEFAULT_PARAMS, API_KEY);
      } catch (error) {
        expect(error).toBeInstanceOf(OpenAIError);
        expect((error as OpenAIError).statusCode).toBe(500);
        expect((error as OpenAIError).isUpstream).toBe(false);
      }
    });

    it("英語テキストの処理が正しく動作する", async () => {
      globalThis.fetch = vi.fn().mockResolvedValue(
        createMockOpenAIResponse(VALID_AI_RESPONSE),
      );

      const result = await processAI(
        { text: "I had a great day today!", language: "en" },
        API_KEY,
      );

      expect(result.summary).toBeDefined();

      // 英語のシステムプロンプトが使われたことを確認
      const callArgs = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]!;
      const body = JSON.parse(callArgs[1].body);
      const systemMessage = body.messages[0];
      expect(systemMessage.content).toContain("text analysis AI assistant");
    });

    it("OpenAI レスポンス構造が不正な場合に 500 をスローする", async () => {
      // choices がない不正なレスポンス
      globalThis.fetch = vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({ id: "chatcmpl-test", object: "chat.completion" }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );

      await expect(processAI(DEFAULT_PARAMS, API_KEY)).rejects.toThrow(OpenAIError);

      try {
        await processAI(DEFAULT_PARAMS, API_KEY);
      } catch (error) {
        expect(error).toBeInstanceOf(OpenAIError);
        expect((error as OpenAIError).statusCode).toBe(500);
      }
    });
  });
});

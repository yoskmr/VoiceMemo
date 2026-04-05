import { z } from "zod";
import type { AIProcessOptions } from "../types.js";
import { getSystemPrompt, buildUserPrompt } from "../prompts/integrated.js";

// --- Constants ---

const MODEL = "gpt-4o-mini";
const TEMPERATURE = 0.3;
const TIMEOUT_MS = 30_000;
const OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions";

// --- OpenAI Response Validation Schema ---

const TagSchema = z.object({
  label: z.string(),
  confidence: z.number().min(0).max(1),
});

const SummarySchema = z.object({
  title: z.string(),
  brief: z.string(),
  key_points: z.array(z.string()),
});

const SentimentScoresSchema = z.object({
  joy: z.number().min(0).max(1),
  sadness: z.number().min(0).max(1),
  anger: z.number().min(0).max(1),
  fear: z.number().min(0).max(1),
  surprise: z.number().min(0).max(1),
  disgust: z.number().min(0).max(1),
  anticipation: z.number().min(0).max(1),
  trust: z.number().min(0).max(1),
});

const SentimentResponseSchema = z.object({
  primary: z.enum([
    "joy", "sadness", "anger", "fear",
    "surprise", "disgust", "anticipation", "trust",
  ]),
  scores: SentimentScoresSchema,
  evidence: z.array(z.string()),
});

const AIResultSchema = z.object({
  summary: SummarySchema.nullable(),
  tags: z.array(TagSchema).nullable(),
  sentiment: SentimentResponseSchema.nullable(),
});

// --- Exported Types ---

export type AIResult = z.infer<typeof AIResultSchema>;

// --- OpenAI Error ---

export class OpenAIError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
    public readonly isUpstream: boolean,
  ) {
    super(message);
    this.name = "OpenAIError";
  }
}

// --- Process AI ---

export interface ProcessAIParams {
  text: string;
  language: "ja" | "en";
  options?: AIProcessOptions;
  context?: string;
}

/**
 * OpenAI Chat Completions API (GPT-4o mini) を呼び出し、
 * テキスト分析結果を返す
 */
export async function processAI(
  params: ProcessAIParams,
  apiKey: string,
): Promise<AIResult> {
  const { text, language, options, context } = params;

  const systemPrompt = getSystemPrompt(language);
  const userPrompt = buildUserPrompt({ text, language, options, context });

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  let response: Response;

  try {
    response = await fetch(OPENAI_CHAT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: TEMPERATURE,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
      }),
      signal: controller.signal,
    });
  } catch (error) {
    clearTimeout(timeoutId);
    const message = error instanceof Error ? error.message : "Unknown fetch error";
    throw new OpenAIError(
      `OpenAI API request failed: ${message}`,
      502,
      true,
    );
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    throw new OpenAIError(
      `OpenAI API returned status ${response.status}`,
      502,
      true,
    );
  }

  // OpenAI レスポンスをパース
  let responseBody: unknown;
  try {
    responseBody = await response.json();
  } catch {
    throw new OpenAIError(
      "Failed to parse OpenAI API response as JSON",
      500,
      false,
    );
  }

  // choices[0].message.content を取得
  const content = extractContent(responseBody);

  // content を JSON パース
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new OpenAIError(
      "Failed to parse AI response content as JSON",
      500,
      false,
    );
  }

  // Zod でバリデーション
  const result = AIResultSchema.safeParse(parsed);
  if (!result.success) {
    throw new OpenAIError(
      `AI response validation failed: ${result.error.message}`,
      500,
      false,
    );
  }

  return result.data;
}

// --- Internal Helpers ---

function extractContent(body: unknown): string {
  if (
    typeof body === "object" && body !== null &&
    "choices" in body && Array.isArray((body as Record<string, unknown>).choices)
  ) {
    const choices = (body as Record<string, unknown>).choices as unknown[];
    const first = choices[0];
    if (
      typeof first === "object" && first !== null &&
      "message" in first
    ) {
      const message = (first as Record<string, unknown>).message;
      if (
        typeof message === "object" && message !== null &&
        "content" in message && typeof (message as Record<string, unknown>).content === "string"
      ) {
        return (message as Record<string, unknown>).content as string;
      }
    }
  }

  throw new OpenAIError(
    "Unexpected OpenAI response structure",
    500,
    false,
  );
}

// --- Process Chat (きおくに聞く) ---

export interface ProcessChatParams {
  question: string;
  contextMemos: Array<{
    id: string;
    title: string;
    text: string;
    date: string;
    emotion?: string;
    tags?: string[];
  }>;
  language: string;
}

export interface ChatResult {
  answer: string;
  referenced_memo_ids: string[];
}

const ChatResultSchema = z.object({
  answer: z.string(),
  referenced_memo_ids: z.array(z.string()),
});

/**
 * OpenAI Chat Completions API を呼び出し、
 * ユーザーのきおく（音声メモ）を参照して質問に回答する
 */
export async function processChat(
  params: ProcessChatParams,
  apiKey: string,
): Promise<ChatResult> {
  const systemPrompt = params.language === "ja"
    ? `あなたはユーザーの「きおく」（音声メモ）を参照して回答するAIです。
以下のルールに従ってください：
- ユーザーのきおくを参照して質問に回答する
- 回答の中で参照したきおくがある場合は [きおくN] の形式で言及する（Nは1始まりの番号）
- 寄り添い型のトーン（「〜のようです」「〜かもしれませんね」）
- 押しつけない（「〜すべき」は使わない）
- 一人称不使用
- JSON形式で回答: { "answer": "回答テキスト", "referenced_memo_ids": ["id1", "id2"] }`
    : `You are an AI that answers questions by referencing the user's voice memos ("memories").
Respond in JSON: { "answer": "...", "referenced_memo_ids": ["id1"] }`;

  const contextText = params.contextMemos.map((memo, i) =>
    `[きおく${i + 1}] ${memo.date} タグ: ${memo.tags?.join(", ") || "なし"} 感情: ${memo.emotion || "未分析"}\nタイトル: ${memo.title}\n内容: ${memo.text}`,
  ).join("\n\n");

  const userPrompt = `${contextText}\n\n質問: ${params.question}`;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  let response: Response;

  try {
    response = await fetch(OPENAI_CHAT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: TEMPERATURE,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
      }),
      signal: controller.signal,
    });
  } catch (error) {
    clearTimeout(timeoutId);
    const message = error instanceof Error ? error.message : "Unknown fetch error";
    throw new OpenAIError(
      `OpenAI API request failed: ${message}`,
      502,
      true,
    );
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    throw new OpenAIError(
      `OpenAI API returned status ${response.status}`,
      502,
      true,
    );
  }

  let responseBody: unknown;
  try {
    responseBody = await response.json();
  } catch {
    throw new OpenAIError(
      "Failed to parse OpenAI API response as JSON",
      500,
      false,
    );
  }

  const content = extractContent(responseBody);

  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new OpenAIError(
      "Failed to parse AI response content as JSON",
      500,
      false,
    );
  }

  const result = ChatResultSchema.safeParse(parsed);
  if (!result.success) {
    throw new OpenAIError(
      `AI response validation failed: ${result.error.message}`,
      500,
      false,
    );
  }

  return result.data;
}

// --- Process Polish (高精度仕上げ) ---

export interface ProcessPolishParams {
  text: string;
  customDictionary?: Array<{ reading: string; display: string }>;
  language: string;
}

export interface PolishResult {
  polished_text: string;
}

const PolishResultSchema = z.object({
  polished_text: z.string(),
});

/**
 * OpenAI Chat Completions API を呼び出し、
 * STT で生成されたテキストを校正・整形する
 */
export async function processPolish(
  params: ProcessPolishParams,
  apiKey: string,
): Promise<PolishResult> {
  const dictSection = params.customDictionary?.length
    ? `\n## カスタム辞書\n以下の読みが出現した場合、正しい表記に置き換えてください：\n${params.customDictionary.map((d) => `- 「${d.reading}」→「${d.display}」`).join("\n")}`
    : "";

  const systemPrompt = params.language === "ja"
    ? `あなたは日本語テキストの校正・整形の専門家です。音声認識（STT）で生成されたテキストを、読みやすく自然な日本語に仕上げてください。

## 仕上げルール
1. フィラー完全除去: 「えーと」「あのー」「まあ」「うーん」「なんか」等を全て除去する
2. 誤変換修正: 同音異義語の誤変換を文脈から推測して修正する
3. 句読点最適化: 適切な位置に「、」「。」を挿入・修正する
4. 言い直し・繰り返しの整理: 同じ内容を繰り返している箇所は、正しい方を1つだけ残す
5. 文体整形: 話し言葉を自然な書き言葉に整える。ただし元のニュアンス・感情・トーンは保持する
6. 主語補完: 省略された主語を、文脈から自然に補完する（過度な補完はしない）
7. 内容保持: 情報を追加・削除しない。話した内容を全て残す。要約しない
${dictSection}

JSON形式で出力: { "polished_text": "仕上げ後のテキスト" }`
    : `You are a text polishing expert. Polish the STT-generated text.
Respond in JSON: { "polished_text": "..." }`;

  const userPrompt = params.text;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  let response: Response;

  try {
    response = await fetch(OPENAI_CHAT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: TEMPERATURE,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
      }),
      signal: controller.signal,
    });
  } catch (error) {
    clearTimeout(timeoutId);
    const message = error instanceof Error ? error.message : "Unknown fetch error";
    throw new OpenAIError(
      `OpenAI API request failed: ${message}`,
      502,
      true,
    );
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    throw new OpenAIError(
      `OpenAI API returned status ${response.status}`,
      502,
      true,
    );
  }

  let responseBody: unknown;
  try {
    responseBody = await response.json();
  } catch {
    throw new OpenAIError(
      "Failed to parse OpenAI API response as JSON",
      500,
      false,
    );
  }

  const content = extractContent(responseBody);

  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new OpenAIError(
      "Failed to parse AI response content as JSON",
      500,
      false,
    );
  }

  const result = PolishResultSchema.safeParse(parsed);
  if (!result.success) {
    throw new OpenAIError(
      `AI response validation failed: ${result.error.message}`,
      500,
      false,
    );
  }

  return result.data;
}

/**
 * モデル名を返す（メタデータ用）
 */
export function getModelName(): string {
  return MODEL;
}

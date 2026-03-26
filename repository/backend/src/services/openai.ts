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

/**
 * モデル名を返す（メタデータ用）
 */
export function getModelName(): string {
  return MODEL;
}

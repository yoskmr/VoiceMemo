import type { AIProcessOptions } from "../types.js";

// --- System Prompt Templates ---

const SYSTEM_PROMPT_JA = `あなたはテキスト分析AIアシスタントです。
与えられたテキストを分析し、指示された処理を実行してください。

必ず以下のJSON形式で回答してください。他のテキストは一切含めないでください。

{
  "summary": {
    "title": "内容を表すタイトル（20文字以内）",
    "brief": "内容の要約（100文字以内）",
    "key_points": ["要点1", "要点2", "要点3"]
  },
  "tags": [
    { "label": "タグ名", "confidence": 0.95 }
  ],
  "sentiment": {
    "primary": "最も強い感情カテゴリ",
    "scores": {
      "joy": 0.0,
      "sadness": 0.0,
      "anger": 0.0,
      "fear": 0.0,
      "surprise": 0.0,
      "disgust": 0.0,
      "anticipation": 0.0,
      "trust": 0.0
    },
    "evidence": ["感情の根拠となるテキスト部分"]
  }
}

感情カテゴリは以下の8種類です: joy, sadness, anger, fear, surprise, disgust, anticipation, trust
各スコアは0.0〜1.0の範囲で、合計が1.0に近くなるようにしてください。
タグは3〜5個、confidence は 0.0〜1.0 で設定してください。`;

const SYSTEM_PROMPT_EN = `You are a text analysis AI assistant.
Analyze the given text and perform the requested processing.

You must respond ONLY in the following JSON format. Do not include any other text.

{
  "summary": {
    "title": "A title representing the content (under 50 chars)",
    "brief": "A brief summary (under 200 chars)",
    "key_points": ["point1", "point2", "point3"]
  },
  "tags": [
    { "label": "tag_name", "confidence": 0.95 }
  ],
  "sentiment": {
    "primary": "the strongest emotion category",
    "scores": {
      "joy": 0.0,
      "sadness": 0.0,
      "anger": 0.0,
      "fear": 0.0,
      "surprise": 0.0,
      "disgust": 0.0,
      "anticipation": 0.0,
      "trust": 0.0
    },
    "evidence": ["text passages that indicate the emotion"]
  }
}

Emotion categories are: joy, sadness, anger, fear, surprise, disgust, anticipation, trust
Each score should be between 0.0 and 1.0, and they should sum to approximately 1.0.
Generate 3-5 tags with confidence between 0.0 and 1.0.`;

// --- User Prompt Builder ---

interface BuildUserPromptParams {
  text: string;
  language: "ja" | "en";
  options?: AIProcessOptions;
  context?: string;
}

/**
 * ユーザープロンプトを構築する
 * options で指定された処理のみを要求し、不要な処理は null で返すよう指示する
 */
export function buildUserPrompt(params: BuildUserPromptParams): string {
  const { text, language, options, context } = params;

  const enableSummary = options?.summary !== false;
  const enableTags = options?.tags !== false;
  const enableSentiment = options?.sentiment !== false;

  const instructions: string[] = [];

  if (language === "ja") {
    instructions.push("以下のテキストを分析してください。");

    if (!enableSummary) instructions.push("summary は null にしてください。");
    if (!enableTags) instructions.push("tags は null にしてください。");
    if (!enableSentiment) instructions.push("sentiment は null にしてください。");

    if (context) {
      instructions.push(`追加コンテキスト: ${context}`);
    }

    instructions.push(`\nテキスト:\n${text}`);
  } else {
    instructions.push("Please analyze the following text.");

    if (!enableSummary) instructions.push("Set summary to null.");
    if (!enableTags) instructions.push("Set tags to null.");
    if (!enableSentiment) instructions.push("Set sentiment to null.");

    if (context) {
      instructions.push(`Additional context: ${context}`);
    }

    instructions.push(`\nText:\n${text}`);
  }

  return instructions.join("\n");
}

/**
 * 言語に応じたシステムプロンプトを返す
 */
export function getSystemPrompt(language: "ja" | "en"): string {
  return language === "ja" ? SYSTEM_PROMPT_JA : SYSTEM_PROMPT_EN;
}

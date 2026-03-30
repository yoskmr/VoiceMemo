import { z } from "zod";

// --- Request Schemas ---

export const DeviceAuthRequestSchema = z.object({
  device_id: z.string().uuid(),
  app_version: z.string(),
  os_version: z.string(),
});

export const AIProcessOptionsSchema = z.object({
  summary: z.boolean().optional(),
  tags: z.boolean().optional(),
  sentiment: z.boolean().optional(),
});

export const AIProcessRequestSchema = z.object({
  text: z.string().min(1).max(30000),
  language: z.enum(["ja", "en"]),
  options: AIProcessOptionsSchema.optional(),
  context: z.string().optional(),
});

// --- Response Schemas ---

export const SentimentCategorySchema = z.enum([
  "joy",
  "sadness",
  "anger",
  "fear",
  "surprise",
  "disgust",
  "anticipation",
  "trust",
]);

export const SentimentSchema = z.object({
  primary: SentimentCategorySchema,
  scores: z.record(SentimentCategorySchema, z.number().min(0).max(1)),
});

export const UsageMetaSchema = z.object({
  prompt_tokens: z.number().int().nonnegative(),
  completion_tokens: z.number().int().nonnegative(),
  total_tokens: z.number().int().nonnegative(),
});

export const AIProcessResponseSchema = z.object({
  summary: z.string().nullable(),
  tags: z.array(z.string()).nullable(),
  sentiment: SentimentSchema.nullable(),
  usage: UsageMetaSchema,
  metadata: z.object({
    model: z.string(),
    processed_at: z.string().datetime(),
    language: z.string(),
  }),
});

export const UsageResponseSchema = z.object({
  used: z.number().int().nonnegative(),
  limit: z.number().int().nonnegative().nullable(),
  plan: z.string(),
  resets_at: z.string().datetime().nullable(),
});

export const ErrorDetailSchema = z.record(z.string(), z.unknown());

export const ErrorResponseSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    details: ErrorDetailSchema.optional(),
    request_id: z.string(),
  }),
});

// --- Subscription Schemas ---

export const SubscriptionVerifyRequestSchema = z.object({
  transaction_id: z.string().min(1),
  product_id: z.string().min(1),
  original_transaction_id: z.string().min(1),
});

export type SubscriptionVerifyRequest = z.infer<typeof SubscriptionVerifyRequestSchema>;

// --- Inferred Types ---

export type DeviceAuthRequest = z.infer<typeof DeviceAuthRequestSchema>;
export type AIProcessOptions = z.infer<typeof AIProcessOptionsSchema>;
export type AIProcessRequest = z.infer<typeof AIProcessRequestSchema>;
export type SentimentCategory = z.infer<typeof SentimentCategorySchema>;
export type Sentiment = z.infer<typeof SentimentSchema>;
export type UsageMeta = z.infer<typeof UsageMetaSchema>;
export type AIProcessResponse = z.infer<typeof AIProcessResponseSchema>;
export type UsageResponse = z.infer<typeof UsageResponseSchema>;
export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

// --- Cloudflare Workers Bindings ---

export interface Env {
  ENVIRONMENT: string;
  OPENAI_API_KEY: string;
  JWT_SECRET: string;
  DB: D1Database;
  KV: KVNamespace;
}

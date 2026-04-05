// --- Constants ---

const FREE_MONTHLY_LIMIT = 10;
const KV_TTL_SECONDS = 3456000; // 40 日

// --- Types ---

export type Plan = "free" | "pro";

export interface UsageInfo {
  used: number;
  limit: number | null;
  plan: Plan;
  resets_at: string | null;
}

// --- KV Key Generation ---

function getUsageKey(deviceId: string, yearMonth: string): string {
  return `usage:${deviceId}:${yearMonth}`;
}

function getCurrentYearMonth(): string {
  // UTC ベースで YYYY-MM を返す（KV キーの一貫性のため）
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

// --- Reset Date Calculation ---

/**
 * 翌月1日 00:00 JST (+09:00) を ISO 8601 形式で返す
 */
export function getResetDate(): string {
  const now = new Date();

  // JST での現在年月を算出（UTC + 9 時間）
  const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const year = jst.getUTCFullYear();
  const month = jst.getUTCMonth(); // 0-indexed

  // 翌月1日 00:00 JST = 翌月1日 00:00 - 9 時間 = 前月末日 15:00 UTC
  let nextYear = year;
  let nextMonth = month + 1;
  if (nextMonth > 11) {
    nextMonth = 0;
    nextYear += 1;
  }

  // 翌月1日 00:00 JST を UTC に変換
  const resetUtc = new Date(Date.UTC(nextYear, nextMonth, 1, 0, 0, 0, 0));
  resetUtc.setTime(resetUtc.getTime() - 9 * 60 * 60 * 1000);

  return resetUtc.toISOString();
}

// --- Usage Operations ---

/**
 * 現在の使用量情報を返却する
 */
export async function getUsage(
  kv: KVNamespace,
  deviceId: string,
  plan: Plan,
): Promise<UsageInfo> {
  const yearMonth = getCurrentYearMonth();
  const key = getUsageKey(deviceId, yearMonth);

  const value = await kv.get(key);
  const used = value !== null ? parseInt(value, 10) : 0;

  const limit = plan === "free" ? FREE_MONTHLY_LIMIT : null;
  const resets_at = plan === "free" ? getResetDate() : null;

  return { used, limit, plan, resets_at };
}

/**
 * 使用量カウントを +1 する（TTL 40 日）
 */
export async function incrementUsage(
  kv: KVNamespace,
  deviceId: string,
): Promise<number> {
  const yearMonth = getCurrentYearMonth();
  const key = getUsageKey(deviceId, yearMonth);

  const current = await kv.get(key);
  const newCount = (current !== null ? parseInt(current, 10) : 0) + 1;

  await kv.put(key, String(newCount), { expirationTtl: KV_TTL_SECONDS });

  return newCount;
}

/**
 * 使用量上限チェック
 * true: 利用可能、false: 上限到達
 */
export async function checkQuota(
  kv: KVNamespace,
  deviceId: string,
  plan: Plan,
): Promise<boolean> {
  // Pro プランは無制限
  if (plan === "pro") {
    return true;
  }

  const yearMonth = getCurrentYearMonth();
  const key = getUsageKey(deviceId, yearMonth);

  const value = await kv.get(key);
  const used = value !== null ? parseInt(value, 10) : 0;

  return used < FREE_MONTHLY_LIMIT;
}

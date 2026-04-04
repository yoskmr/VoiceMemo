import { describe, it, expect, beforeEach } from "vitest";
import {
  getUsage,
  incrementUsage,
  checkQuota,
  getResetDate,
  type Plan,
} from "../../src/services/quota.js";

// --- In-memory KV Mock ---

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

// --- Constants ---

const DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000";

describe("quota service", () => {
  let kv: ReturnType<typeof createMockKV>;

  beforeEach(() => {
    kv = createMockKV();
  });

  describe("getUsage", () => {
    it("初期状態で used: 0, limit: 10 を返す（free プラン）", async () => {
      const usage = await getUsage(kv, DEVICE_ID, "free");

      expect(usage.used).toBe(0);
      expect(usage.limit).toBe(10);
      expect(usage.plan).toBe("free");
      expect(usage.resets_at).toBeDefined();
    });

    it("Pro プランで limit: null を返す", async () => {
      const usage = await getUsage(kv, DEVICE_ID, "pro");

      expect(usage.used).toBe(0);
      expect(usage.limit).toBeNull();
      expect(usage.plan).toBe("pro");
      expect(usage.resets_at).toBeNull();
    });
  });

  describe("incrementUsage", () => {
    it("カウントが +1 される", async () => {
      const count1 = await incrementUsage(kv, DEVICE_ID);
      expect(count1).toBe(1);

      const count2 = await incrementUsage(kv, DEVICE_ID);
      expect(count2).toBe(2);

      const count3 = await incrementUsage(kv, DEVICE_ID);
      expect(count3).toBe(3);
    });

    it("KV に TTL 40 日で保存される", async () => {
      await incrementUsage(kv, DEVICE_ID);

      // ストアに保存された TTL を確認
      const entries = Array.from(kv._store.values());
      expect(entries.length).toBe(1);
      expect(entries[0]!.ttl).toBe(3456000);
    });

    it("getUsage で increment 後の値が反映される", async () => {
      await incrementUsage(kv, DEVICE_ID);
      await incrementUsage(kv, DEVICE_ID);
      await incrementUsage(kv, DEVICE_ID);

      const usage = await getUsage(kv, DEVICE_ID, "free");
      expect(usage.used).toBe(3);
    });
  });

  describe("checkQuota", () => {
    it("上限未到達で true を返す", async () => {
      const result = await checkQuota(kv, DEVICE_ID, "free");
      expect(result).toBe(true);
    });

    it("上限到達（10 回）で false を返す", async () => {
      // 10 回インクリメント
      for (let i = 0; i < 10; i++) {
        await incrementUsage(kv, DEVICE_ID);
      }

      const result = await checkQuota(kv, DEVICE_ID, "free");
      expect(result).toBe(false);
    });

    it("9 回使用で true（上限未到達）", async () => {
      for (let i = 0; i < 9; i++) {
        await incrementUsage(kv, DEVICE_ID);
      }

      const result = await checkQuota(kv, DEVICE_ID, "free");
      expect(result).toBe(true);
    });

    it("Pro プランで常に true を返す", async () => {
      // 100 回使っても Pro は無制限
      for (let i = 0; i < 100; i++) {
        await incrementUsage(kv, DEVICE_ID);
      }

      const result = await checkQuota(kv, DEVICE_ID, "pro");
      expect(result).toBe(true);
    });
  });

  describe("getResetDate", () => {
    it("翌月1日 00:00 JST の ISO 文字列を返す", () => {
      const resetDate = getResetDate();

      // ISO 8601 形式であること
      expect(resetDate).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z$/);

      // 翌月1日であること（UTC 換算で前月末 15:00）
      const reset = new Date(resetDate);
      const jstReset = new Date(reset.getTime() + 9 * 60 * 60 * 1000);

      // JST で 00:00 であること
      expect(jstReset.getUTCHours()).toBe(0);
      expect(jstReset.getUTCMinutes()).toBe(0);
      expect(jstReset.getUTCSeconds()).toBe(0);

      // JST で1日であること
      expect(jstReset.getUTCDate()).toBe(1);

      // 未来の日付であること
      expect(reset.getTime()).toBeGreaterThan(Date.now());
    });
  });
});

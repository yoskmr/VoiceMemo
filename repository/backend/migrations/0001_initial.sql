-- devices テーブル: デバイス認証情報
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  plan TEXT NOT NULL DEFAULT 'free',
  app_version TEXT,
  os_version TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_devices_plan ON devices(plan);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_at);

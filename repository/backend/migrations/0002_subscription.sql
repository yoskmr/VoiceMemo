-- サブスクリプション管理用カラム追加
ALTER TABLE devices ADD COLUMN product_id TEXT;
ALTER TABLE devices ADD COLUMN subscription_expires_at TEXT;
ALTER TABLE devices ADD COLUMN original_transaction_id TEXT;

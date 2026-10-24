ALTER TABLE stops ADD COLUMN IF NOT EXISTS provider TEXT CHECK (provider IN ('busan','tago','normalized'));
UPDATE stops SET provider='busan' WHERE id LIKE 'busan-%' AND provider IS NULL;

ALTER TABLE stops ADD COLUMN IF NOT EXISTS provider_ars_no TEXT;
ALTER TABLE bus_arrival_cache ADD COLUMN IF NOT EXISTS routes JSONB NOT NULL DEFAULT '[]';
CREATE INDEX IF NOT EXISTS stops_provider_ars_idx ON stops(provider_ars_no);

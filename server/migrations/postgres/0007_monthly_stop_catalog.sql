CREATE TABLE bus_catalog_regions (
  provider TEXT NOT NULL CHECK(provider IN ('busan','tago')),
  city_code TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL,
  synced_at TIMESTAMPTZ,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  page INTEGER NOT NULL DEFAULT 1,
  expected_total INTEGER,
  last_error TEXT,
  PRIMARY KEY(provider,city_code)
);
CREATE TABLE bus_catalog_staging (
  provider TEXT NOT NULL,
  city_code TEXT NOT NULL,
  stop_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  PRIMARY KEY(provider,city_code,stop_id)
);
CREATE TABLE bus_catalog_entries (
  provider TEXT NOT NULL,
  city_code TEXT NOT NULL,
  stop_id TEXT NOT NULL REFERENCES stops(id),
  PRIMARY KEY(provider,city_code,stop_id)
);
CREATE TABLE bus_catalog_discovery (
  provider TEXT PRIMARY KEY,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Keep previously searched stops available during the initial full collection.
INSERT INTO bus_catalog_entries SELECT provider,coalesce(provider_city_code,''),id
FROM stops WHERE provider IN ('busan','tago') ON CONFLICT DO NOTHING;
CREATE INDEX bus_catalog_entries_stop_idx ON bus_catalog_entries(stop_id);

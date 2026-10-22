ALTER TABLE stops ADD COLUMN IF NOT EXISTS provider_city_code TEXT;

-- Provider forecasts, never ground-truth arrival events or model-generated values.
CREATE TABLE bus_arrival_observations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  stop_id TEXT NOT NULL REFERENCES stops(id) ON DELETE CASCADE,
  route_id TEXT NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expected_at TIMESTAMPTZ NOT NULL,
  eta_seconds INTEGER NOT NULL CHECK (eta_seconds BETWEEN 0 AND 14400),
  arrival_rank INTEGER NOT NULL CHECK (arrival_rank > 0),
  provider TEXT NOT NULL,
  provider_key TEXT NOT NULL,
  UNIQUE(stop_id, route_id, provider_key, observed_at, expected_at)
);
CREATE INDEX bus_history_lookup_idx ON bus_arrival_observations(stop_id, route_id, observed_at DESC) WHERE arrival_rank=1;
CREATE INDEX bus_history_retention_idx ON bus_arrival_observations(fetched_at);

CREATE TABLE bus_arrival_cache (
  stop_id TEXT PRIMARY KEY REFERENCES stops(id) ON DELETE CASCADE,
  fetched_at TIMESTAMPTZ,
  provider_key TEXT,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT '-infinity',
  payload JSONB NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'not_collected'
);
CREATE TABLE bus_provider_daily_usage (
  day DATE PRIMARY KEY,
  requests INTEGER NOT NULL CHECK (requests > 0)
);

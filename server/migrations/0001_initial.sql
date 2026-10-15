PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS stops (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  provider_stop_id TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS stops_location_idx ON stops(latitude, longitude);

CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stop_id TEXT NOT NULL REFERENCES stops(id) ON DELETE CASCADE,
  route_id TEXT NOT NULL,
  route_name TEXT,
  radius_meters INTEGER NOT NULL DEFAULT 30 CHECK (radius_meters BETWEEN 10 AND 500),
  eta_threshold_minutes INTEGER NOT NULL DEFAULT 5 CHECK (eta_threshold_minutes BETWEEN 1 AND 30),
  schedule_start TEXT NOT NULL DEFAULT '00:00',
  schedule_end TEXT NOT NULL DEFAULT '23:59',
  timezone TEXT NOT NULL DEFAULT 'Asia/Seoul',
  weekdays TEXT NOT NULL DEFAULT '[1,2,3,4,5,6,7]',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, stop_id, route_id)
);
CREATE INDEX IF NOT EXISTS subscriptions_user_enabled_idx ON subscriptions(user_id, enabled);

CREATE TABLE IF NOT EXISTS device_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('ios','android','web')),
  token TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(platform, token)
);

CREATE TABLE IF NOT EXISTS alert_events (
  id TEXT PRIMARY KEY,
  subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
  eta_minutes REAL NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS alert_cooldown_idx ON alert_events(subscription_id, created_at);

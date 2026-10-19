-- Additive SQLite migration; legacy subscription data is preserved.
CREATE TABLE api_devices (
 token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 label TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE routes (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, direction TEXT NOT NULL, destination TEXT NOT NULL
);
CREATE TABLE route_stops (
 route_id TEXT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
 sequence INTEGER NOT NULL CHECK(sequence >= 0), stop_id TEXT NOT NULL REFERENCES stops(id),
 offset_seconds INTEGER NOT NULL CHECK(offset_seconds >= 0),
 PRIMARY KEY(route_id, sequence)
);
CREATE INDEX route_stops_stop_idx ON route_stops(stop_id, route_id);
CREATE TABLE trips (
 id TEXT PRIMARY KEY, route_id TEXT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
 service_date TEXT NOT NULL, source TEXT NOT NULL
);
CREATE TABLE stop_times (
 trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
 sequence INTEGER NOT NULL, stop_id TEXT NOT NULL REFERENCES stops(id),
 arrival_at TEXT NOT NULL, departure_at TEXT NOT NULL,
 predicted_arrival_at TEXT, predicted_departure_at TEXT, observed_at TEXT,
 PRIMARY KEY(trip_id, sequence)
);
CREATE INDEX stop_times_departure_idx ON stop_times(departure_at, stop_id);
CREATE TABLE headway_windows (
 id TEXT PRIMARY KEY, route_id TEXT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
 service_date TEXT NOT NULL, first_departure_at TEXT NOT NULL, last_departure_at TEXT NOT NULL,
 headway_seconds INTEGER NOT NULL CHECK(headway_seconds BETWEEN 60 AND 14400), source TEXT NOT NULL
);
CREATE TABLE transfers (
 from_stop_id TEXT NOT NULL REFERENCES stops(id), to_stop_id TEXT NOT NULL REFERENCES stops(id),
 walk_seconds INTEGER NOT NULL CHECK(walk_seconds BETWEEN 0 AND 1800),
 PRIMARY KEY(from_stop_id,to_stop_id)
);
CREATE TABLE saved_journeys (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 name TEXT NOT NULL, origin_stop_id TEXT NOT NULL REFERENCES stops(id),
 destination_stop_id TEXT NOT NULL REFERENCES stops(id),
 weekdays TEXT NOT NULL, departure_time TEXT NOT NULL,
 timezone TEXT NOT NULL DEFAULT 'Asia/Seoul', created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX saved_journeys_user_idx ON saved_journeys(user_id);
CREATE TABLE journey_options (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 request_json TEXT NOT NULL, option_json TEXT NOT NULL, expires_at TEXT NOT NULL
);
CREATE INDEX journey_options_expiry_idx ON journey_options(expires_at);
CREATE TABLE journey_sessions (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 option_json TEXT NOT NULL, current_leg INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL CHECK(status IN ('waiting','riding','transfer','completed','cancelled','disrupted')),
 revision INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX journey_sessions_user_idx ON journey_sessions(user_id,status);
CREATE TABLE journey_alerts (
 id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES journey_sessions(id) ON DELETE CASCADE,
 leg_index INTEGER NOT NULL, vehicle_key TEXT NOT NULL, kind TEXT NOT NULL,
 body_json TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')),
 acknowledged_at TEXT, UNIQUE(session_id,leg_index,vehicle_key,kind)
);
CREATE INDEX journey_alerts_pending_idx ON journey_alerts(session_id,acknowledged_at);

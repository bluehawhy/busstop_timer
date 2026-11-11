-- Officially verified route geometry, separate from route_stops (which do not define road paths).
-- GeoJSON LineString coordinates are WGS84 [longitude,latitude].
CREATE TABLE IF NOT EXISTS bus_route_shapes (
  route_id TEXT PRIMARY KEY,
  route_name TEXT NOT NULL,
  source TEXT NOT NULL,
  geometry JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

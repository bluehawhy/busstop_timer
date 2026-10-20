import { ApiError } from './planner.js';
const date = v => typeof v === 'string' && /T.*(Z|[+-]\d{2}:\d{2})$/.test(v) && Number.isFinite(Date.parse(v));
const text = v => typeof v === 'string' && v.length > 0 && v.length < 200;
const time = v => date(v) ? new Date(v).toISOString() : null;

// Administrator-only atomic normalized import. Never deletes existing catalogue rows.
export async function importCatalog(db, input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new ApiError('INVALID_CATALOG');
  const keys = ['stops','routes','routeStops','trips','stopTimes','transfers','headways'];
  for (const key of keys) if (input[key] && (!Array.isArray(input[key]) || input[key].length > 20000)) throw new ApiError('INVALID_CATALOG');
  return db.transaction(async()=>{
    for (const s of input.stops ?? []) {
      if (!text(s.id) || !text(s.name) || !Number.isFinite(s.latitude) || !Number.isFinite(s.longitude) ||
        Math.abs(s.latitude)>90 || Math.abs(s.longitude)>180) throw new ApiError('INVALID_STOP');
      (await db.prepare(`INSERT INTO stops(id,name,latitude,longitude) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO UPDATE
        SET name=excluded.name,latitude=excluded.latitude,longitude=excluded.longitude,updated_at=to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`)
        .run(s.id,s.name,s.latitude,s.longitude));
    }
    for (const r of input.routes ?? []) {
      if (![r.id,r.name,r.direction,r.destination].every(text)) throw new ApiError('INVALID_ROUTE');
      (await db.prepare(`INSERT INTO routes VALUES($1,$2,$3,$4) ON CONFLICT(id) DO UPDATE SET name=excluded.name,
        direction=excluded.direction,destination=excluded.destination`).run(r.id,r.name,r.direction,r.destination));
    }
    for (const s of input.routeStops ?? []) {
      if (!text(s.routeId)||!text(s.stopId)||!Number.isInteger(s.sequence)||!Number.isInteger(s.offsetSeconds)) throw new ApiError('INVALID_ROUTE_STOP');
      (await db.prepare(`INSERT INTO route_stops VALUES($1,$2,$3,$4) ON CONFLICT(route_id,sequence) DO UPDATE
        SET stop_id=excluded.stop_id,offset_seconds=excluded.offset_seconds`).run(s.routeId,s.sequence,s.stopId,s.offsetSeconds));
    }
    for (const t of input.trips ?? []) {
      if (![t.id,t.routeId,t.source].every(text)||!/^\d{4}-\d{2}-\d{2}$/.test(t.serviceDate)) throw new ApiError('INVALID_TRIP');
      (await db.prepare(`INSERT INTO trips VALUES($1,$2,$3,$4) ON CONFLICT(id) DO UPDATE SET route_id=excluded.route_id,
        service_date=excluded.service_date,source=excluded.source`).run(t.id,t.routeId,t.serviceDate,t.source));
    }
    for (const s of input.stopTimes ?? []) {
      if (!text(s.tripId)||!text(s.stopId)||!Number.isInteger(s.sequence)||s.sequence<0||
        !date(s.arrivalAt)||!date(s.departureAt)||Date.parse(s.departureAt)<Date.parse(s.arrivalAt)||
        (s.predictedArrivalAt != null && !date(s.predictedArrivalAt)) ||
        (s.predictedDepartureAt != null && !date(s.predictedDepartureAt)) ||
        ((s.predictedArrivalAt || s.predictedDepartureAt) && !date(s.observedAt))) throw new ApiError('INVALID_STOP_TIME');
      (await db.prepare(`INSERT INTO stop_times VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(trip_id,sequence) DO UPDATE SET
        stop_id=excluded.stop_id,arrival_at=excluded.arrival_at,departure_at=excluded.departure_at,
        predicted_arrival_at=excluded.predicted_arrival_at,predicted_departure_at=excluded.predicted_departure_at,observed_at=excluded.observed_at`)
        .run(s.tripId,s.sequence,s.stopId,time(s.arrivalAt),time(s.departureAt),time(s.predictedArrivalAt),time(s.predictedDepartureAt),time(s.observedAt)));
    }
    for (const t of input.transfers ?? []) {
      if (!text(t.fromStopId)||!text(t.toStopId)||!Number.isInteger(t.walkSeconds)) throw new ApiError('INVALID_TRANSFER');
      (await db.prepare(`INSERT INTO transfers VALUES($1,$2,$3) ON CONFLICT(from_stop_id,to_stop_id)
        DO UPDATE SET walk_seconds=excluded.walk_seconds`).run(t.fromStopId,t.toStopId,t.walkSeconds));
    }
    for (const h of input.headways ?? []) {
      if (![h.id,h.routeId,h.source].every(text)||!/^\d{4}-\d{2}-\d{2}$/.test(h.serviceDate)||
        !date(h.firstDepartureAt)||!date(h.lastDepartureAt)||Date.parse(h.lastDepartureAt)<Date.parse(h.firstDepartureAt)||
        Date.parse(h.lastDepartureAt)-Date.parse(h.firstDepartureAt)>86400000||!Number.isInteger(h.headwaySeconds)) throw new ApiError('INVALID_HEADWAY');
      (await db.prepare(`INSERT INTO headway_windows VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(id) DO UPDATE SET
        route_id=excluded.route_id,service_date=excluded.service_date,first_departure_at=excluded.first_departure_at,
        last_departure_at=excluded.last_departure_at,headway_seconds=excluded.headway_seconds,source=excluded.source`)
        .run(h.id,h.routeId,h.serviceDate,time(h.firstDepartureAt),time(h.lastDepartureAt),h.headwaySeconds,h.source));
    }
    const broken=(await db.prepare(`SELECT a.trip_id FROM stop_times a JOIN stop_times b
      ON a.trip_id=b.trip_id AND a.sequence<b.sequence WHERE a.departure_at>=b.arrival_at LIMIT 1`).get());
    const offsets=(await db.prepare(`SELECT a.route_id FROM route_stops a JOIN route_stops b
      ON a.route_id=b.route_id AND a.sequence<b.sequence WHERE a.offset_seconds>=b.offset_seconds LIMIT 1`).get());
    if(broken||offsets) throw new ApiError('NON_MONOTONIC_TIMES');
    return { imported: Object.fromEntries(keys.map(k => [k,(input[k]??[]).length])) };
  }).catch(error=>{
    if (error instanceof ApiError) throw error;
    throw new ApiError('CATALOG_CONSTRAINT_VIOLATION');
  });
}

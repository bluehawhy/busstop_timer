const ms = value => Date.parse(value);
const iso = value => new Date(value).toISOString();
const MINUTE = 60000;
export class ApiError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
export function validateSearch(input, now = Date.now()) {
  const depart = ms(input.departureAt);
  const compareCount = input.compareCount ?? 1;
  const compareStepMinutes = input.compareStepMinutes ?? 15;
  const maxTransfers = input.maxTransfers ?? 2;
  const bufferSeconds = input.bufferSeconds ?? 120;
  if (typeof input.originStopId !== 'string' || typeof input.destinationStopId !== 'string' ||
    input.originStopId === input.destinationStopId || !Number.isFinite(depart) ||
    depart < now - MINUTE || depart > now + 7 * 86400000 ||
    !Number.isInteger(compareCount) || compareCount < 1 || compareCount > 8 ||
    !Number.isInteger(compareStepMinutes) || compareStepMinutes < 5 || compareStepMinutes > 120 ||
    !Number.isInteger(maxTransfers) || maxTransfers < 0 || maxTransfers > 2 ||
    !Number.isInteger(bufferSeconds) || bufferSeconds < 0 || bufferSeconds > 900) {
    throw new ApiError('INVALID_SEARCH');
  }
  return { originStopId: input.originStopId, destinationStopId: input.destinationStopId,
    departureAt: iso(depart), compareCount, compareStepMinutes, maxTransfers, bufferSeconds };
}

export async function loadRides(db, now, start, end) {
  const rows = (await db.prepare(`SELECT s.*, t.route_id, t.source, r.name, r.direction, r.destination,
    p.name AS stop_name FROM stop_times s JOIN trips t ON t.id=s.trip_id
    JOIN routes r ON r.id=t.route_id JOIN stops p ON p.id=s.stop_id
    WHERE t.id IN (SELECT trip_id FROM stop_times WHERE departure_at BETWEEN $1 AND $2)
    ORDER BY t.id,s.sequence`).all(iso(start - 86400000), iso(end + 86400000)));
  const groups = new Map();
  for (const row of rows) {
    if (!groups.has(row.trip_id)) groups.set(row.trip_id, []);
    const observed = ms(row.observed_at);
    const fresh = observed <= now + 30000 && now - observed <= 120000;
    groups.get(row.trip_id).push({ ...row,
      arrival: fresh && row.predicted_arrival_at ? ms(row.predicted_arrival_at) : ms(row.arrival_at),
      departure: fresh && row.predicted_departure_at ? ms(row.predicted_departure_at) : ms(row.departure_at),
      basis: fresh && row.predicted_departure_at ? 'realtime' : 'timetable' });
  }
  const windows = (await db.prepare(`SELECT h.*,r.name,r.direction,r.destination FROM headway_windows h
    JOIN routes r ON r.id=h.route_id WHERE first_departure_at <= $1 AND last_departure_at >= $2`)
    .all(iso(end), iso(start - 86400000)));
  for (const window of windows) {
    const stops = (await db.prepare(`SELECT rs.*,p.name AS stop_name FROM route_stops rs JOIN stops p ON p.id=rs.stop_id
      WHERE route_id=$1 ORDER BY sequence`).all(window.route_id));
    for (let departure = ms(window.first_departure_at), count = 0;
      departure <= ms(window.last_departure_at) && departure <= end && count < 1500;
      departure += window.headway_seconds * 1000, count++) {
      const key = `headway:${window.id}:${departure}`;
      groups.set(key, stops.map(s => ({ ...s, ...window, stop_id: s.stop_id, stop_name: s.stop_name,
        trip_id: key, arrival: departure + s.offset_seconds * 1000,
        departure: departure + s.offset_seconds * 1000, basis: 'headway' })));
    }
  }
  const rides = new Map();
  for (const stops of groups.values()) {
    for (let i = 0; i < stops.length - 1; i++) {
      const a = stops[i];
      if (a.departure < start || a.departure > end) continue;
      for (let j = i + 1; j < stops.length; j++) {
        const b = stops[j];
        if (b.arrival <= a.departure || b.arrival > end) continue;
        if (!rides.has(a.stop_id)) rides.set(a.stop_id, []);
        rides.get(a.stop_id).push({ routeId: a.route_id, routeName: a.name, direction: a.direction,
          destination: a.destination, vehicleKey: a.trip_id, fromStopId: a.stop_id, fromStopName: a.stop_name,
          toStopId: b.stop_id, toStopName: b.stop_name, departureAt: iso(a.departure), arrivalAt: iso(b.arrival),
          basis: a.basis === 'realtime' && b.predicted_arrival_at ? 'realtime' : a.basis,
          source: a.source, observedAt: a.observed_at ?? null });
      }
    }
  }
  for (const list of rides.values()) list.sort((a,b) => ms(a.departureAt) - ms(b.departureAt));
  return rides;
}

export async function plan(db, request, now = Date.now()) {
  const start = ms(request.departureAt);
  const end = start + (request.compareCount - 1) * request.compareStepMinutes * MINUTE + 4 * 3600000;
  const rides = await loadRides(db, now, start, end);
  const transfers = (await db.prepare(`SELECT * FROM transfers`).all());
  const comparisons = [];
  for (let slot = 0; slot < request.compareCount; slot++) {
    const departure = start + slot * request.compareStepMinutes * MINUTE;
    const queue = [{ stop: request.originStopId, time: departure, legs: [], visited: [request.originStopId] }];
    const options = []; let expanded = 0;
    while (queue.length && expanded++ < 10000) {
      queue.sort((a,b) => a.time - b.time);
      const state = queue.shift();
      if (state.stop === request.destinationStopId && state.legs.length) {
        const waits = state.legs.reduce((sum,l) => sum + l.waitSeconds, 0);
        options.push({ departureAt: iso(departure), arrivalAt: iso(state.time),
          durationSeconds: (state.time-departure)/1000, transfers: state.legs.length-1,
          waitSeconds: waits, walkSeconds: state.legs.reduce((sum,l) => sum+l.walkSeconds,0), legs: state.legs });
        if (options.length >= 30) break;
        continue;
      }
      if (state.legs.length >= request.maxTransfers + 1) continue;
      const links = [{ to_stop_id: state.stop, walk_seconds: 0 },
        ...(state.legs.length ? transfers.filter(t => t.from_stop_id === state.stop && t.to_stop_id !== state.stop) : [])];
      for (const link of links) {
        const buffer = state.legs.length ? request.bufferSeconds : 0;
        const ready = state.time + (link.walk_seconds + buffer) * 1000;
        // Retain multiple departures on every route, including the following vehicle.
        for (const ride of rides.get(link.to_stop_id) ?? []) {
          const dep = ms(ride.departureAt);
          if (dep < ready || dep > departure + 4 * 3600000 || state.visited.includes(ride.toStopId) ||
            state.legs.some(l => l.vehicleKey === ride.vehicleKey)) continue;
          if (queue.length > 20000) break;
          queue.push({ stop: ride.toStopId, time: ms(ride.arrivalAt),
            legs: [...state.legs, { ...ride, walkSeconds: link.walk_seconds, bufferSeconds: buffer,
              waitSeconds: (dep - state.time)/1000 - link.walk_seconds, readyAt: iso(ready) }],
            visited: [...state.visited, ride.toStopId] });
        }
      }
    }
    const unique = new Map();
    for (const option of options.sort((a,b) => ms(a.arrivalAt)-ms(b.arrivalAt))) {
      const key = option.legs.map(l => `${l.vehicleKey}:${l.fromStopId}:${l.toStopId}`).join('|');
      if (!unique.has(key)) unique.set(key, option);
    }
    comparisons.push({ departureAt: iso(departure), options: [...unique.values()].slice(0,12),
      limited: expanded >= 10000 || queue.length > 20000 });
  }
  return comparisons;
}

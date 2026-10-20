import { haversineMeters, isWithinSchedule, normalizeArrivals, shouldAlert } from './arrival.js';

const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
});
const bad = (message, status = 400) => json({ error: message }, status);
const id = () => crypto.randomUUID();

function cors(_request, response) {
  const headers = new Headers(response.headers);
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  return new Response(response.body, { status: response.status, headers });
}

async function requireApiKey(request, env) {
  // Configure API_BEARER_TOKEN for private preview deployments. Production mobile apps
  // need per-user identity (OIDC/Firebase Auth/Cloudflare Access), never a bundled shared secret.
  return Boolean(env.API_BEARER_TOKEN) &&
    request.headers.get('Authorization') === `Bearer ${env.API_BEARER_TOKEN}`;
}

async function arrivalsFor(env, stopId) {
  if (!env.BUS_ARRIVALS_URL) return [];
  const url = new URL(env.BUS_ARRIVALS_URL);
  url.searchParams.set('stopId', stopId);
  const response = await fetch(url, { headers: env.BUS_API_KEY ? { authorization: `Bearer ${env.BUS_API_KEY}` } : {} });
  if (!response.ok) throw new Error('BUS_PROVIDER_UNAVAILABLE');
  return normalizeArrivals(await response.json());
}

async function evaluate(request, env) {
  let body;
  try { body = await request.json(); } catch { return bad('INVALID_JSON'); }
  const { userId, latitude, longitude, accuracyMeters = 0, recordedAt } = body ?? {};
  if (typeof userId !== 'string' || !userId || !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) || !Number.isFinite(accuracyMeters) ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 ||
      accuracyMeters < 0 || accuracyMeters > Number(env.MAX_LOCATION_ACCURACY_METERS ?? 100)) {
    return bad('INVALID_LOCATION');
  }
  const now = new Date(recordedAt ?? Date.now());
  if (!Number.isFinite(now.getTime()) || Math.abs(Date.now() - now.getTime()) > 5 * 60_000) return bad('STALE_LOCATION');
  await env.DB.prepare(`INSERT INTO users(id) VALUES ($1) ON CONFLICT DO NOTHING`).bind(userId).run();
  // Coordinates are evaluated in memory and are deliberately not persisted to D1.

  const { results: subscriptions } = await env.DB.prepare(`SELECT s.*, p.latitude AS stop_lat,p.longitude AS stop_lon,p.name AS stop_name
    FROM subscriptions s JOIN stops p ON p.id=s.stop_id WHERE s.user_id=$1 AND s.enabled=1`).bind(userId).all();
  const events = [];
  let feed;
  try {
    const stopIds = [...new Set(subscriptions.map((s) => s.stop_id))];
    feed = (await Promise.all(stopIds.map((stopId) => arrivalsFor(env, stopId)))).flat();
  } catch {
    return json({ alerts: [], providerStatus: 'unavailable', evaluatedAt: now.toISOString() }, 503);
  }
  for (const sub of subscriptions) {
    let weekdays;
    try { weekdays = JSON.parse(sub.weekdays); } catch { continue; }
    if (!isWithinSchedule(now, sub.schedule_start, sub.schedule_end, weekdays, sub.timezone)) continue;
    const distance = haversineMeters(latitude, longitude, sub.stop_lat, sub.stop_lon);
    const arrival = feed.find((row) => row.stopId === sub.stop_id && row.routeId === sub.route_id);
    if (!arrival || !shouldAlert({ distanceMeters: distance, radiusMeters: sub.radius_meters,
      accuracyMeters, etaMinutes: arrival.etaMinutes, thresholdMinutes: sub.eta_threshold_minutes })) continue;
    const recent = await env.DB.prepare(`SELECT id FROM alert_events WHERE subscription_id=$1
      AND created_at >= to_char((CURRENT_TIMESTAMP - INTERVAL '10 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') LIMIT 1`).bind(sub.id).first();
    if (recent) continue;
    const event = { id: id(), subscriptionId: sub.id, stopName: sub.stop_name, routeId: sub.route_id,
      routeName: sub.route_name, etaMinutes: arrival.etaMinutes, distanceMeters: Math.round(distance) };
    await env.DB.prepare(`INSERT INTO alert_events(id,subscription_id,eta_minutes) VALUES ($1,$2,$3)`)
      .bind(event.id, sub.id, event.etaMinutes).run();
    events.push(event);
  }
  return json({ alerts: events, providerStatus: env.BUS_ARRIVALS_URL ? 'ok' : 'not_configured',
    evaluatedAt: now.toISOString() });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return cors(request, new Response(null, { status: 204 }));
    if (!await requireApiKey(request, env)) return cors(request, bad('UNAUTHORIZED', 401));
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    try {
      if (path === '/health' && request.method === 'GET') return cors(request, json({ ok: true }));
      if (path === '/api/stops' && request.method === 'GET') {
        const lat = Number(url.searchParams.get('lat')); const lon = Number(url.searchParams.get('lon'));
        const radius = Math.min(Math.max(Number(url.searchParams.get('radius') || 1000), 50), 5000);
        if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return cors(request, bad('INVALID_COORDINATES'));
        const dLat = radius / 111_000; const dLon = radius / (111_000 * Math.max(Math.cos(lat * Math.PI / 180), 0.01));
        const { results } = await env.DB.prepare(`SELECT * FROM stops WHERE latitude BETWEEN $1 AND $2 AND longitude BETWEEN $3 AND $4`)
          .bind(lat - dLat, lat + dLat, lon - dLon, lon + dLon).all();
        return cors(request, json(results.map((s) => ({ ...s, distanceMeters: Math.round(haversineMeters(lat, lon, s.latitude, s.longitude)) }))
          .filter((s) => s.distanceMeters <= radius).sort((a,b) => a.distanceMeters - b.distanceMeters)));
      }
      if (path === '/api/stops' && request.method === 'POST') {
        const b = await request.json();
        if (!b?.id || !b?.name || !Number.isFinite(b.latitude) || !Number.isFinite(b.longitude) ||
          Math.abs(b.latitude) > 90 || Math.abs(b.longitude) > 180) return cors(request, bad('INVALID_STOP'));
        await env.DB.prepare(`INSERT INTO stops(id,name,latitude,longitude,provider_stop_id) VALUES($1,$2,$3,$4,$5)
          ON CONFLICT(id) DO UPDATE SET name=excluded.name,latitude=excluded.latitude,longitude=excluded.longitude,
          provider_stop_id=excluded.provider_stop_id,updated_at=to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`)
          .bind(String(b.id), String(b.name), b.latitude, b.longitude, b.providerStopId ?? null).run();
        return cors(request, json({ id: String(b.id) }, 201));
      }
      if (path === '/api/subscriptions' && request.method === 'POST') {
        const b = await request.json();
        const radius = Number(b?.radiusMeters ?? env.DEFAULT_RADIUS_METERS ?? 30);
        const threshold = Number(b?.etaThresholdMinutes ?? 5);
        const weekdays = b?.weekdays ?? [1,2,3,4,5,6,7];
        if (!b?.userId || !b?.stopId || !b?.routeId || radius < 10 || radius > 500 ||
          threshold < 1 || threshold > 30 || !Array.isArray(weekdays) ||
          weekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7) ||
          !/^([01]\d|2[0-3]):[0-5]\d$/.test(b.scheduleStart ?? '00:00') ||
          !/^([01]\d|2[0-3]):[0-5]\d$/.test(b.scheduleEnd ?? '23:59')) return cors(request, bad('INVALID_SUBSCRIPTION'));
        const timezone = b.timezone ?? 'Asia/Seoul';
        try { new Intl.DateTimeFormat('en-US', { timeZone: timezone }); }
        catch { return cors(request, bad('INVALID_TIMEZONE')); }
        const subscriptionId = id();
        await env.DB.prepare(`INSERT INTO users(id) VALUES ($1) ON CONFLICT DO NOTHING`).bind(String(b.userId)).run();
        await env.DB.prepare(`INSERT INTO subscriptions(id,user_id,stop_id,route_id,route_name,radius_meters,
          eta_threshold_minutes,schedule_start,schedule_end,weekdays,timezone) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`)
          .bind(subscriptionId, String(b.userId), String(b.stopId), String(b.routeId), b.routeName ?? null,
            radius, threshold, b.scheduleStart ?? '00:00', b.scheduleEnd ?? '23:59', JSON.stringify(weekdays), timezone).run();
        return cors(request, json({ id: subscriptionId }, 201));
      }
      if (path === '/api/subscriptions' && request.method === 'GET') {
        const userId = url.searchParams.get('userId');
        if (!userId) return cors(request, bad('USER_ID_REQUIRED'));
        const { results } = await env.DB.prepare(`SELECT * FROM subscriptions WHERE user_id=$1 ORDER BY created_at DESC`).bind(userId).all();
        return cors(request, json(results));
      }
      const deletion = path.match(/^\/api\/subscriptions\/([\w-]+)$/);
      if (deletion && request.method === 'DELETE') {
        const userId = url.searchParams.get('userId');
        if (!userId) return cors(request, bad('USER_ID_REQUIRED'));
        await env.DB.prepare(`DELETE FROM subscriptions WHERE id=$1 AND user_id=$2`).bind(deletion[1], userId).run();
        return cors(request, json({ deleted: true }));
      }
      if (path === '/api/evaluate' && request.method === 'POST') return cors(request, await evaluate(request, env));
      if (path === '/api/arrivals' && request.method === 'GET') {
        const stopId = url.searchParams.get('stopId');
        if (!stopId) return cors(request, bad('STOP_ID_REQUIRED'));
        const rows = await arrivalsFor(env, stopId);
        return cors(request, json({ arrivals: rows, providerStatus: env.BUS_ARRIVALS_URL ? 'ok' : 'not_configured' }));
      }
      return cors(request, bad('NOT_FOUND', 404));
    } catch (error) {
      return cors(request, json({ error: error?.message === 'BUS_PROVIDER_UNAVAILABLE' ? error.message : 'INTERNAL_ERROR' }, 500));
    }
  },
};

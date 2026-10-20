import { ApiError } from './planner.js';
import { fetchBusArrivals, providerConfigured, providerKey } from './bus-provider.js';

export async function refreshStop(db, stop, env = process.env) {
  if (!providerConfigured(env)) return 'not_configured';
  await db.prepare('INSERT INTO bus_arrival_cache(stop_id) VALUES($1) ON CONFLICT DO NOTHING').run(stop.id);
  // A database lease deduplicates HTTP requests and workers, including failures.
  const lease = await db.prepare(`UPDATE bus_arrival_cache SET next_attempt_at=now()+interval '30 seconds'
    WHERE stop_id=$1 AND next_attempt_at<=now() RETURNING stop_id`).get(stop.id);
  if (!lease) return 'cached';
  try {
    const configuredLimit = Number(env.BUS_PROVIDER_DAILY_LIMIT ?? 9000);
    const limit = Number.isInteger(configuredLimit) && configuredLimit > 0 ? configuredLimit : 9000;
    const quota = await db.prepare(`INSERT INTO bus_provider_daily_usage(day,requests)
      VALUES((now() AT TIME ZONE 'Asia/Seoul')::date,1) ON CONFLICT(day) DO UPDATE
      SET requests=bus_provider_daily_usage.requests+1 WHERE bus_provider_daily_usage.requests<$1 RETURNING requests`).get(limit);
    if (!quota) throw new ApiError('BUS_PROVIDER_DAILY_LIMIT', 503);
    const feed = await fetchBusArrivals(stop, env);
    await db.transaction(async () => {
      // Only stored stop/route subscriptions train the history; never model output.
      const saved = await db.prepare('SELECT DISTINCT route_id FROM subscriptions WHERE stop_id=$1 AND enabled=1').all(stop.id);
      const routeIds = new Set(saved.map(row => row.route_id));
      const ranks = new Map();
      const records = [];
      for (const row of feed.arrivals) {
        const rank = (ranks.get(row.routeId) ?? 0) + 1;
        ranks.set(row.routeId, rank);
        if (!routeIds.has(row.routeId)) continue;
        records.push({route_id:row.routeId,observed_at:row.observedAt,expected_at:row.expectedAt,
          eta_seconds:row.etaSeconds,arrival_rank:rank});
      }
      if (records.length) await db.prepare(`INSERT INTO bus_arrival_observations
        (stop_id,route_id,observed_at,fetched_at,expected_at,eta_seconds,arrival_rank,provider,provider_key)
        SELECT $1,x.route_id,x.observed_at,$2::timestamptz,x.expected_at,x.eta_seconds,x.arrival_rank,$3,$4
        FROM jsonb_to_recordset($5::jsonb) AS x(route_id text,observed_at timestamptz,
          expected_at timestamptz,eta_seconds integer,arrival_rank integer)
        ON CONFLICT DO NOTHING`).run(stop.id,feed.fetchedAt,feed.provider,providerKey(stop,env),JSON.stringify(records));
      await db.prepare(`UPDATE bus_arrival_cache SET fetched_at=$1,payload=$2::jsonb,status='ok',provider_key=$4 WHERE stop_id=$3`)
        .run(feed.fetchedAt,JSON.stringify(feed.arrivals),stop.id,providerKey(stop,env));
    });
    return 'ok';
  } catch (error) {
    // Do not log provider URLs or keys; retain last good payload, but label it stale.
    const code = error instanceof ApiError ? error.message : 'BUS_COLLECTION_FAILED';
    await db.prepare('UPDATE bus_arrival_cache SET status=$1 WHERE stop_id=$2').run(code,stop.id);
    return code;
  }
}

const quantile = (sorted, proportion) => {
  const position = (sorted.length - 1) * proportion, lower = Math.floor(position), upper = Math.ceil(position);
  return Math.round(sorted[lower] + (sorted[upper] - sorted[lower]) * (position-lower));
};
export async function predictArrival(db, stop, routeId, at = new Date(), env = process.env) {
  const stopId=stop.id;
  // Seoul local weekday and a circular +/-30 minute window handle midnight.
  // At most ONE nearest observation per local day avoids repeated polling bias.
  const samples = await db.prepare(`WITH candidates AS (
    SELECT eta_seconds, observed_at,
      abs(extract(epoch FROM ((observed_at AT TIME ZONE 'Asia/Seoul')::time - ($3::timestamptz AT TIME ZONE 'Asia/Seoul')::time))) AS delta
    FROM bus_arrival_observations
    WHERE stop_id=$1 AND route_id=$2 AND arrival_rank=1 AND provider_key=$4
      AND observed_at>=now()-interval '90 days'
      AND observed_at < date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') AT TIME ZONE 'Asia/Seoul'
      AND extract(isodow FROM observed_at AT TIME ZONE 'Asia/Seoul')=extract(isodow FROM $3::timestamptz AT TIME ZONE 'Asia/Seoul')
  ), ranked AS (
    SELECT *,row_number() OVER (PARTITION BY (observed_at AT TIME ZONE 'Asia/Seoul')::date
      ORDER BY least(delta,86400-delta),observed_at DESC) AS position
    FROM candidates WHERE least(delta,86400-delta)<=1800
  ) SELECT eta_seconds,observed_at FROM ranked WHERE position=1 ORDER BY observed_at DESC LIMIT 12`)
    .all(stopId,routeId,at.toISOString(),providerKey(stop,env));
  const count = samples.length;
  if (count < 3) return { stopId,routeId,basis:'unavailable',reason:'INSUFFICIENT_HISTORY',sampleDays:count,minimumSampleDays:3 };
  const seconds = samples.map(row => row.eta_seconds).sort((a,b) => a-b);
  const median = seconds.length % 2 ? seconds[Math.floor(count/2)] : Math.round((seconds[count/2-1]+seconds[count/2])/2);
  return {stopId,routeId,basis:'historical_estimate',confidence:'low',
    etaSeconds:median,etaMinutes:Math.ceil(median/60),expectedAt:new Date(at.getTime()+median*1000).toISOString(),
    rangeSeconds:{low:quantile(seconds,0.1),high:quantile(seconds,0.9)},sampleDays:count,
    latestSampleAt:new Date(samples[0].observed_at).toISOString(),
    method:'same_weekday_nearest_time_per_day_median',windowMinutes:30,historyDays:90,
    observationKind:'provider_forecast',holidayAdjusted:false};
}

export async function arrivalsView(db, stop, routes, env = process.env) {
  const refreshStatus = await refreshStop(db,stop,env);
  const cache = await db.prepare('SELECT * FROM bus_arrival_cache WHERE stop_id=$1').get(stop.id);
  const now = Date.now();
  const fresh = cache?.provider_key === providerKey(stop,env) && cache?.status === 'ok' && now - new Date(cache.fetched_at).getTime() <= 90000;
  const values = [];
  for (const route of routes) {
    const live = fresh ? cache.payload.filter(row => row.routeId === route.route_id && Date.parse(row.expectedAt) >= now && now-Date.parse(row.observedAt)<=90000) : [];
    if (live.length) {
      values.push(...live.map(row => ({...row,etaSeconds:Math.max(0,Math.ceil((Date.parse(row.expectedAt)-now)/1000)),
        etaMinutes:Math.max(0,Math.ceil((Date.parse(row.expectedAt)-now)/60000)),basis:'realtime',fetchedAt:new Date(cache.fetched_at).toISOString()})));
    } else {
      values.push({...await predictArrival(db,stop,route.route_id,new Date(),env),routeName:route.route_name ?? route.route_id,
        fallbackReason:refreshStatus === 'ok' || refreshStatus === 'cached' ? cache?.status === 'ok' ? 'NO_LIVE_ARRIVAL' : cache?.status : refreshStatus});
    }
  }
  return {stopId:stop.id,stopName:stop.name,arrivals:values,providerStatus:refreshStatus,lastProviderStatus:cache?.status??'not_collected',
    lastFetchedAt:cache?.fetched_at ? new Date(cache.fetched_at).toISOString() : null,generatedAt:new Date(now).toISOString()};
}

export async function collectSavedArrivals(db, env = process.env) {
  await db.prepare("DELETE FROM bus_arrival_observations WHERE fetched_at<now()-interval '90 days'").run();
  await db.prepare("DELETE FROM bus_provider_daily_usage WHERE day<current_date-90").run();
  if (!providerConfigured(env)) return;
  const raw = Number(env.BUS_COLLECTION_BATCH_SIZE ?? 5);
  const count = Number.isInteger(raw) && raw>0 && raw<=100 ? raw : 5;
  const stops = await db.prepare(`SELECT p.* FROM stops p LEFT JOIN bus_arrival_cache c ON c.stop_id=p.id
    WHERE EXISTS(SELECT 1 FROM subscriptions s WHERE s.stop_id=p.id AND s.enabled=1)
      AND (c.next_attempt_at IS NULL OR c.next_attempt_at<=now())
    ORDER BY c.next_attempt_at ASC NULLS FIRST,p.id LIMIT $1`).all(count);
  for (const stop of stops) await refreshStop(db,stop,env);

}

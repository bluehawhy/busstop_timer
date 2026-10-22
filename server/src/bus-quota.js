import { ApiError } from './planner.js';

// Shared allowance for arrivals and catalogue searches; failed calls also count.
export async function reserveProviderRequest(db, env = process.env) {
  const raw = Number(env.BUS_PROVIDER_DAILY_LIMIT ?? 9000);
  const limit = Number.isInteger(raw) && raw > 0 ? raw : 9000;
  const row = await db.prepare(`INSERT INTO bus_provider_daily_usage(day,requests)
    VALUES((now() AT TIME ZONE 'Asia/Seoul')::date,1) ON CONFLICT(day) DO UPDATE
    SET requests=bus_provider_daily_usage.requests+1 WHERE bus_provider_daily_usage.requests<$1 RETURNING requests`).get(limit);
  if (!row) throw new ApiError('BUS_PROVIDER_DAILY_LIMIT', 503);
}

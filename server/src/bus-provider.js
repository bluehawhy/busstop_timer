import { ApiError } from './planner.js';
import { fetchBusanArrivals } from './busan-provider.js';

const number = value => value !== null && value !== undefined && value !== '' && Number.isFinite(Number(value));
export function providerName(env) {
  return ['busan','tago'].includes(env.BUS_PROVIDER) ? env.BUS_PROVIDER : 'normalized';
}
export function providerKey(stop, env = process.env) {
  return `${providerName(env)}:${stop.provider_city_code ?? ''}:${stop.provider_stop_id || stop.id}`;
}
export function providerConfigured(env) {
  if (env.BUS_PROVIDER === 'busan') return Boolean(env.BUSAN_SERVICE_KEY?.trim());
  return env.BUS_PROVIDER === 'tago' ? Boolean(env.TAGO_SERVICE_KEY) : Boolean(env.BUS_ARRIVALS_URL);
}

// All URLs come from server configuration, never client input.
export async function fetchBusArrivals(stop, env = process.env) {
  if (!providerConfigured(env)) throw new ApiError('BUS_PROVIDER_NOT_CONFIGURED', 503);
  if (providerName(env) === 'busan') return fetchBusanArrivals(stop,env);
  const tago = providerName(env) === 'tago';
  if (tago && (!stop.provider_stop_id || !/^\d{1,8}$/.test(stop.provider_city_code ?? ''))) {
    throw new ApiError('STOP_PROVIDER_MAPPING_REQUIRED', 409);
  }
  const url = new URL(tago
    ? 'https://apis.data.go.kr/1613000/ArvlInfoInqireService/getSttnAcctoArvlPrearngeInfoList'
    : env.BUS_ARRIVALS_URL);
  const headers = {};
  if (tago) {
    // Use the decoded service key: URLSearchParams performs URL encoding once.
    url.searchParams.set('serviceKey', env.TAGO_SERVICE_KEY);
    url.searchParams.set('cityCode', stop.provider_city_code);
    url.searchParams.set('nodeId', stop.provider_stop_id);
    url.searchParams.set('_type', 'json');
    url.searchParams.set('numOfRows', '1000');
    url.searchParams.set('pageNo', '1');
  } else {
    url.searchParams.set('stopId', stop.provider_stop_id || stop.id);
    if (env.BUS_API_KEY) headers.authorization = `Bearer ${env.BUS_API_KEY}`;
  }
  let payload;
  try {
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error();
    payload = await response.json();
  } catch { throw new ApiError('BUS_PROVIDER_UNAVAILABLE', 502); }
  let rows;
  if (tago) {
    if (String(payload?.response?.header?.resultCode) !== '00') throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE', 502);
    const body = payload.response.body;
    if (!body || !number(body.totalCount) || Number(body.totalCount) > 1000) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE', 502);
    const items = body.items?.item;
    rows = Number(body.totalCount) === 0 ? [] : Array.isArray(items) ? items : items ? [items] : null;
    if (rows && rows.length !== Number(body.totalCount)) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE', 502);
  } else {
    rows = Array.isArray(payload) ? payload : payload?.arrivals;
  }
  if (!Array.isArray(rows) || rows.length > 1000) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE', 502);
  const fetchedAt = new Date().toISOString();
  const arrivals = rows.map(row => {
    const routeId = tago ? row.routeid : row.routeId;
    const seconds = tago ? row.arrtime : number(row.etaMinutes) ? Number(row.etaMinutes) * 60 : null;
    const sourceAt = !tago && row.updatedAt != null ? Date.parse(row.updatedAt) : Date.parse(fetchedAt);
    if (!routeId || String(routeId).length > 199 || !number(seconds) || seconds < 0 || seconds > 14400 ||
      !Number.isFinite(sourceAt) || Date.parse(fetchedAt) - sourceAt > 90000 || sourceAt - Date.parse(fetchedAt) > 30000 ||
      (!tago && String(row.stopId) !== String(stop.provider_stop_id || stop.id))) {
      throw new ApiError('BUS_PROVIDER_INVALID_OR_STALE_ROW', 502);
    }
    return { stopId: stop.id, routeId: String(routeId), routeName: String((tago ? row.routeno : row.routeName) ?? routeId).slice(0,199),
      etaSeconds: Math.round(Number(seconds)), observedAt: new Date(sourceAt).toISOString(),
      expectedAt: new Date(sourceAt + Number(seconds) * 1000).toISOString(),
      remainingStops: number(row.arrprevstationcnt) ? Number(row.arrprevstationcnt) : null };
  }).sort((a,b) => Date.parse(a.expectedAt) - Date.parse(b.expectedAt));
  return { arrivals, fetchedAt, provider: providerName(env) };
}

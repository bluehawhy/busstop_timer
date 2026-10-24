import { randomUUID } from 'node:crypto';
import { providerKey, providerName, providerConfigured, stopEnvironment } from './bus-provider.js';
import { tagoCities, searchTagoStops } from './tago-catalog.js';
import { searchBusanStops } from './busan-provider.js';
import { reserveProviderRequest } from './bus-quota.js';
import { ApiError } from './planner.js';
import { arrivalsView, predictArrival, refreshStop } from './bus-history.js';
let cityCache;
async function availableCities(db) {
  const env=process.env;
  const cities=env.BUSAN_SERVICE_KEY?.trim() ? [{provider:'busan',cityCode:null,name:'부산광역시'}] : [];
  if(env.TAGO_SERVICE_KEY?.trim()) {
    if(!cityCache || cityCache.key!==env.TAGO_SERVICE_KEY || cityCache.expires<Date.now()) {
      const rows=await tagoCities(env,()=>reserveProviderRequest(db));
      cityCache={key:env.TAGO_SERVICE_KEY,rows,expires:Date.now()+3600000};
    }
    cities.push(...cityCache.rows);
  }
  return cities;
}
const text = v => typeof v==='string' && v.length>0 && v.length<200;
async function stopById(db,id) {
  if (!text(id)) throw new ApiError('INVALID_STOP_ID');
  const stop=await db.prepare('SELECT * FROM stops WHERE id=$1').get(id);
  if(!stop) throw new ApiError('STOP_NOT_FOUND',404);
  return stop;
}
export async function busApi(request,db,user,admin,path) {
  if(!path.startsWith('/api/bus/')) return null;
  const url=new URL(request.url),method=request.method;
  if(path==='/api/bus/cities'&&method==='GET') return Response.json({cities:await availableCities(db)});
  if(path==='/api/bus/stops/search'&&method==='GET') {
    const provider=url.searchParams.get('provider')??(process.env.BUS_PROVIDER==='auto'?'busan':providerName(process.env));
    const cityCode=url.searchParams.get('cityCode');
    if(!['busan','tago'].includes(provider)) throw new ApiError('UNSUPPORTED_BUS_PROVIDER',409);
    if(!providerConfigured({...process.env,BUS_PROVIDER:provider})) throw new ApiError('BUS_PROVIDER_NOT_CONFIGURED',503);
    const query=(url.searchParams.get('q')??'').trim(),arsNo=url.searchParams.get('arsNo');
    const page=Number(url.searchParams.get('page')??1);
    if((arsNo!==null&&!(provider==='busan'?/^\d{5}$/:/^\d{1,10}$/).test(arsNo))||(!arsNo&&(query.length<2||query.length>50))||
      !Number.isInteger(page)||page<1||page>1000) throw new ApiError('INVALID_STOP_SEARCH');
    if(provider==='tago' && !(await availableCities(db)).some(c=>c.provider==='tago'&&c.cityCode===cityCode)) throw new ApiError('UNSUPPORTED_CITY',409);
    await reserveProviderRequest(db);
    const result=provider==='busan' ? await searchBusanStops({query,arsNo,page}) : await searchTagoStops({query,arsNo,page,cityCode});
    await db.transaction(async()=>{
      for(const stop of result.stops) await db.prepare(`INSERT INTO stops
        (id,name,latitude,longitude,provider_stop_id,provider_ars_no,provider_city_code,provider) VALUES($1,$2,$3,$4,$5,$6,$7,$8)
        ON CONFLICT(id) DO UPDATE SET name=excluded.name,latitude=excluded.latitude,
          longitude=excluded.longitude,provider_stop_id=excluded.provider_stop_id,provider_ars_no=excluded.provider_ars_no,provider_city_code=excluded.provider_city_code,provider=excluded.provider,
          updated_at=to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`)
        .run(stop.id,stop.name,stop.latitude,stop.longitude,stop.providerStopId,stop.arsNo,stop.cityCode??null,provider);
    });
    return Response.json({...result,basis:'provider_catalog',provider,cityCode:provider==='tago'?cityCode:null});
  }
  if(path==='/api/bus/stops'&&method==='GET') {
    const q=(url.searchParams.get('q')??'').trim().slice(0,100);
    return Response.json({stops:await db.prepare(`SELECT id,name,latitude,longitude,provider_stop_id,provider_city_code,provider_ars_no FROM stops
      WHERE strpos(lower(name),lower($1))>0 OR id=$1 OR provider_ars_no=$1 ORDER BY name LIMIT 100`).all(q)});
  }
  const mapping=path.match(/^\/api\/bus\/stops\/([\w-]+)\/provider$/);
  if(mapping&&method==='POST') {
    if(!admin) throw new ApiError('FORBIDDEN',403);
    const b=await request.json();
    const mappedStop=await stopById(db,mapping[1]);
    const selected=providerName(stopEnvironment(mappedStop));
    const busan=selected==='busan';
    if(!text(b.providerStopId)||(busan?!/^\d{1,20}$/.test(b.providerStopId):!/^\d{1,8}$/.test(b.cityCode??''))) throw new ApiError('INVALID_PROVIDER_MAPPING');
    await db.transaction(async()=>{
      await db.prepare('UPDATE stops SET provider_stop_id=$1,provider_city_code=$2,provider=$4 WHERE id=$3').run(b.providerStopId,busan?null:b.cityCode,mapping[1],selected);
      await db.prepare('DELETE FROM bus_arrival_cache WHERE stop_id=$1').run(mapping[1]);
      // History keeps its provider identity; predictions ignore old mappings.
    });
    return Response.json({updated:true});
  }
  if(path==='/api/bus/routes'&&method==='GET') {
    const stop=await stopById(db,url.searchParams.get('stopId'));
    const providerStatus=await refreshStop(db,stop);
    const cache=await db.prepare('SELECT payload,routes,fetched_at,status,provider_key FROM bus_arrival_cache WHERE stop_id=$1').get(stop.id);
    const routes=await db.prepare(`SELECT DISTINCT r.id AS "routeId",r.name AS "routeName",r.direction FROM routes r JOIN route_stops rs ON rs.route_id=r.id WHERE rs.stop_id=$1`).all(stop.id);
    const map=new Map(routes.map(r=>[r.routeId,r]));
    if(cache?.provider_key===providerKey(stop) && cache?.status==='ok' && Date.now()-new Date(cache.fetched_at).getTime()<90000) for(const row of cache.routes) {
      if(!map.has(row.routeId)) map.set(row.routeId,{routeId:row.routeId,routeName:row.routeName,direction:null});
    }
    return Response.json({stopId:stop.id,routes:[...map.values()],providerStatus,
      coverage:providerName(stopEnvironment(stop))==='busan'?'catalog_and_provider_stop_routes':'catalog_and_current_arrivals',note:'공급자 응답과 DB 카탈로그 기준입니다. 공급자가 누락한 노선의 전체 운행 여부는 보장하지 않습니다.'});
  }
  if(path==='/api/bus/subscriptions'&&method==='GET') return Response.json({subscriptions:await db.prepare(`SELECT s.id,s.stop_id AS "stopId",p.name AS "stopName",
    s.route_id AS "routeId",s.route_name AS "routeName",s.enabled,p.latitude,p.longitude
    FROM subscriptions s JOIN stops p ON p.id=s.stop_id WHERE s.user_id=$1 ORDER BY s.created_at DESC`).all(user)});
  if(path==='/api/bus/subscriptions'&&method==='POST') {
    const b=await request.json(),stop=await stopById(db,b.stopId);
    if(!text(b.routeId)||(b.enabled!==undefined&&typeof b.enabled!=='boolean')) throw new ApiError('INVALID_SUBSCRIPTION');
    const existing=await db.prepare('SELECT id,route_name FROM subscriptions WHERE user_id=$1 AND stop_id=$2 AND route_id=$3').get(user,stop.id,b.routeId);
    let routeName=existing?.route_name;
    if(!existing) {
      const known=await db.prepare(`SELECT r.name FROM routes r JOIN route_stops rs ON r.id=rs.route_id WHERE r.id=$1 AND rs.stop_id=$2 LIMIT 1`).get(b.routeId,stop.id);
      const cache=await db.prepare('SELECT payload,routes,fetched_at,status,provider_key FROM bus_arrival_cache WHERE stop_id=$1').get(stop.id);
      const live=cache?.provider_key===providerKey(stop) && cache?.status==='ok' && Date.now()-new Date(cache.fetched_at).getTime()<90000 ? cache.routes.find(r=>r.routeId===b.routeId) : null;
      if(!known&&!live) throw new ApiError('ROUTE_NOT_FOUND_AT_STOP',404);
      routeName=known?.name??live.routeName;
    }
    const result=await db.transaction(async()=>{
      await db.prepare('SELECT id FROM users WHERE id=$1 FOR UPDATE').get(user);
      const count=await db.prepare('SELECT count(*)::int AS count FROM subscriptions WHERE user_id=$1').get(user);
      if(!existing&&count.count>=100) throw new ApiError('SUBSCRIPTION_LIMIT',409);
      return db.prepare(`INSERT INTO subscriptions(id,user_id,stop_id,route_id,route_name,enabled) VALUES($1,$2,$3,$4,$5,$6)
        ON CONFLICT(user_id,stop_id,route_id) DO UPDATE SET enabled=excluded.enabled RETURNING id`).get(randomUUID(),user,stop.id,b.routeId,routeName,b.enabled===false?0:1);
    });
    return Response.json({id:result.id}, {status:existing?200:201});
  }
  const subscription=path.match(/^\/api\/bus\/subscriptions\/([\w-]+)$/);
  if(subscription&&method==='DELETE') {
    await db.prepare('DELETE FROM subscriptions WHERE id=$1 AND user_id=$2').run(subscription[1],user);
    return Response.json({deleted:true});
  }
  if((path==='/api/bus/arrivals'||path==='/api/bus/predictions')&&method==='GET') {
    const stop=await stopById(db,url.searchParams.get('stopId'));
    const routes=await db.prepare('SELECT route_id,route_name FROM subscriptions WHERE user_id=$1 AND stop_id=$2 AND enabled=1').all(user,stop.id);
    if(!routes.length) throw new ApiError('STOP_NOT_SAVED',403);
    if(path==='/api/bus/arrivals') return Response.json(await arrivalsView(db,stop,routes));
    const routeId=url.searchParams.get('routeId');
    if(!routes.some(r=>r.route_id===routeId)) throw new ApiError('ROUTE_NOT_SAVED',403);
    const value=url.searchParams.get('at');
    if(value&&!/T.*(Z|[+-]\d{2}:\d{2})$/.test(value)) throw new ApiError('TIMEZONE_REQUIRED');
    const at=new Date(value??Date.now());
    if(!Number.isFinite(at.getTime())||at.getTime()<Date.now()-60000||at.getTime()>Date.now()+7*86400000) throw new ApiError('INVALID_PREDICTION_TIME');
    return Response.json(await predictArrival(db,stop,routeId,at));
  }
  throw new ApiError('NOT_FOUND',404);
}

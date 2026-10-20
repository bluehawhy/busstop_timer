import { randomUUID } from 'node:crypto';
import { providerKey } from './bus-provider.js';
import { ApiError } from './planner.js';
import { arrivalsView, predictArrival, refreshStop } from './bus-history.js';
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
  if(path==='/api/bus/stops'&&method==='GET') {
    const q=(url.searchParams.get('q')??'').trim().slice(0,100);
    return Response.json({stops:await db.prepare(`SELECT id,name,latitude,longitude,provider_stop_id,provider_city_code FROM stops
      WHERE strpos(lower(name),lower($1))>0 OR id=$1 ORDER BY name LIMIT 100`).all(q)});
  }
  const mapping=path.match(/^\/api\/bus\/stops\/([\w-]+)\/provider$/);
  if(mapping&&method==='POST') {
    if(!admin) throw new ApiError('FORBIDDEN',403);
    await stopById(db,mapping[1]);
    const b=await request.json();
    if(!text(b.providerStopId)||!/^\d{1,8}$/.test(b.cityCode??'')) throw new ApiError('INVALID_PROVIDER_MAPPING');
    await db.transaction(async()=>{
      await db.prepare('UPDATE stops SET provider_stop_id=$1,provider_city_code=$2 WHERE id=$3').run(b.providerStopId,b.cityCode,mapping[1]);
      await db.prepare('DELETE FROM bus_arrival_cache WHERE stop_id=$1').run(mapping[1]);
      // History keeps its provider identity; predictions ignore old mappings.
    });
    return Response.json({updated:true});
  }
  if(path==='/api/bus/routes'&&method==='GET') {
    const stop=await stopById(db,url.searchParams.get('stopId'));
    const providerStatus=await refreshStop(db,stop);
    const cache=await db.prepare('SELECT payload,fetched_at,status,provider_key FROM bus_arrival_cache WHERE stop_id=$1').get(stop.id);
    const routes=await db.prepare(`SELECT DISTINCT r.id AS "routeId",r.name AS "routeName",r.direction FROM routes r JOIN route_stops rs ON rs.route_id=r.id WHERE rs.stop_id=$1`).all(stop.id);
    const map=new Map(routes.map(r=>[r.routeId,r]));
    if(cache?.provider_key===providerKey(stop) && cache?.status==='ok' && Date.now()-new Date(cache.fetched_at).getTime()<90000) for(const row of cache.payload) {
      if(!map.has(row.routeId)) map.set(row.routeId,{routeId:row.routeId,routeName:row.routeName,direction:null});
    }
    return Response.json({stopId:stop.id,routes:[...map.values()],providerStatus,
      coverage:'catalog_and_current_arrivals',note:'현재 도착정보에 없는 노선은 카탈로그 등록 전까지 목록에서 빠질 수 있습니다.'});
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
      const cache=await db.prepare('SELECT payload,fetched_at,status,provider_key FROM bus_arrival_cache WHERE stop_id=$1').get(stop.id);
      const live=cache?.provider_key===providerKey(stop) && cache?.status==='ok' && Date.now()-new Date(cache.fetched_at).getTime()<90000 ? cache.payload.find(r=>r.routeId===b.routeId) : null;
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

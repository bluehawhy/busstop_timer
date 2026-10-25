import { searchBusanStops } from './busan-provider.js';
import { searchTagoStops, tagoCities, tagoKey } from './tago-catalog.js';
import { reserveProviderRequest } from './bus-quota.js';
import { ApiError } from './planner.js';

export async function catalogCities(db) {
  return db.prepare(`SELECT provider,nullif(city_code,'') AS "cityCode",name,
    synced_at AS "syncedAt" FROM bus_catalog_regions ORDER BY provider,city_code`).all();
}

export async function searchCatalog(db,{provider,cityCode,query,arsNo,page}) {
  const region=await db.prepare('SELECT synced_at,last_error FROM bus_catalog_regions WHERE provider=$1 AND city_code=$2')
    .get(provider,cityCode??'');
  if(!region) throw new ApiError('BUS_CATALOG_NOT_READY',503);
  const args=[provider,cityCode??'',query,arsNo??null];
  const where=`FROM bus_catalog_entries e JOIN stops s ON s.id=e.stop_id
    WHERE e.provider=$1 AND e.city_code=$2
    AND (($4::text IS NOT NULL AND s.provider_ars_no=$4)
      OR ($4::text IS NULL AND strpos(lower(s.name),lower($3))>0))`;
  const count=await db.prepare('SELECT count(*)::int AS total '+where).get(...args);
  if(!region.synced_at && count.total===0) throw new ApiError('BUS_CATALOG_NOT_READY',503);
  const stops=await db.prepare(`SELECT s.id,s.name,s.latitude,s.longitude,
    s.provider_stop_id AS "providerStopId",s.provider_ars_no AS "arsNo",
    nullif(s.provider_city_code,'') AS "cityCode" ${where}
    ORDER BY s.name,s.id LIMIT 100 OFFSET $5`).all(...args,(page-1)*100);
  return {stops,totalCount:count.total,page,pageSize:100,basis:'database_catalog',
    provider,cityCode:cityCode??null,syncedAt:region.synced_at,refreshPending:!region.synced_at};
}

async function discover(db,env) {
  if(env.BUSAN_SERVICE_KEY?.trim()) await db.prepare(`INSERT INTO bus_catalog_regions(provider,city_code,name)
    VALUES('busan','','부산광역시') ON CONFLICT DO NOTHING`).run();
  if(!tagoKey(env,'ArvlInfoInqireService')||!tagoKey(env,'BusSttnInfoInqireService')) return;
  await db.prepare("INSERT INTO bus_catalog_discovery(provider) VALUES('tago') ON CONFLICT DO NOTHING").run();
  const due=await db.prepare("SELECT provider FROM bus_catalog_discovery WHERE provider='tago' AND next_attempt_at<=now()").get();
  if(!due) return;
  try {
    const cities=await tagoCities(env,()=>reserveProviderRequest(db,env));
    await db.transaction(async()=>{
      for(const city of cities) await db.prepare(`INSERT INTO bus_catalog_regions(provider,city_code,name)
        VALUES($1,$2,$3) ON CONFLICT(provider,city_code) DO UPDATE SET name=excluded.name`)
        .run(city.provider,city.cityCode,city.name);
      await db.prepare("UPDATE bus_catalog_discovery SET next_attempt_at=now()+interval '1 month' WHERE provider='tago'").run();
    });
  } catch(error) {
    await db.prepare("UPDATE bus_catalog_discovery SET next_attempt_at=now()+interval '1 hour' WHERE provider='tago'").run();
    console.error('Bus catalog city discovery failed:',error instanceof ApiError?error.message:'INTERNAL_ERROR');
  }
}

// One small batch per minute. Cursor and staging survive server restarts.
// A session advisory lock prevents overlapping collectors across server instances.
export async function collectStopCatalog(db,env=process.env) {
  await db.withConnection(async()=>{
    const lock=await db.prepare('SELECT pg_try_advisory_lock(798231605) AS acquired').get();
    if(!lock.acquired) return;
    try {
      await discover(db,env);
      for(let batch=0;batch<5;batch++) {
        const region=await db.prepare(`SELECT * FROM bus_catalog_regions
          WHERE next_attempt_at<=now() AND
          ((provider='busan' AND $1) OR (provider='tago' AND $2))
          ORDER BY next_attempt_at,provider,city_code LIMIT 1`)
          .get(Boolean(env.BUSAN_SERVICE_KEY?.trim()),Boolean(tagoKey(env,'BusSttnInfoInqireService')));
        if(!region) break;
        const args=[region.provider,region.city_code];
        try {
          await reserveProviderRequest(db,env);
          const result=region.provider==='busan'
            ? await searchBusanStops({page:region.page},env)
            : await searchTagoStops({cityCode:region.city_code,page:region.page},env);
          const total=result.totalCount;
          if(!Number.isSafeInteger(total)||total<0||total>1000000||
            (region.expected_total!==null&&region.expected_total!==total)||
            (total>0&&!result.stops.length)) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE',502);
          await db.transaction(async()=>{
            for(const stop of result.stops) await db.prepare(`INSERT INTO bus_catalog_staging
              (provider,city_code,stop_id,payload) VALUES($1,$2,$3,$4::jsonb) ON CONFLICT DO NOTHING`)
              .run(...args,stop.id,JSON.stringify(stop));
            const seen=await db.prepare('SELECT count(*)::int AS count FROM bus_catalog_staging WHERE provider=$1 AND city_code=$2').get(...args);
            if(seen.count>total) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE',502);
            const complete=region.page*result.pageSize>=total;
            if(!complete) {
              if(region.page>=10000) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE',502);
              await db.prepare(`UPDATE bus_catalog_regions SET page=page+1,expected_total=$3,last_error=NULL
                WHERE provider=$1 AND city_code=$2`).run(...args,total);
              return;
            }
            if(seen.count!==total) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE',502);
            // Publish only a complete snapshot; never delete saved stops/subscriptions.
            await db.prepare(`INSERT INTO stops(id,name,latitude,longitude,provider_stop_id,provider_ars_no,provider_city_code,provider)
              SELECT stop_id,payload->>'name',(payload->>'latitude')::double precision,
                (payload->>'longitude')::double precision,payload->>'providerStopId',payload->>'arsNo',nullif(city_code,''),provider
              FROM bus_catalog_staging WHERE provider=$1 AND city_code=$2
              ON CONFLICT(id) DO UPDATE SET name=excluded.name,latitude=excluded.latitude,
                longitude=excluded.longitude,provider_stop_id=excluded.provider_stop_id,
                provider_ars_no=excluded.provider_ars_no,provider_city_code=excluded.provider_city_code,
                provider=excluded.provider,updated_at=to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`).run(...args);
            await db.prepare('DELETE FROM bus_catalog_entries WHERE provider=$1 AND city_code=$2').run(...args);
            await db.prepare(`INSERT INTO bus_catalog_entries SELECT provider,city_code,stop_id FROM bus_catalog_staging
              WHERE provider=$1 AND city_code=$2`).run(...args);
            await db.prepare('DELETE FROM bus_catalog_staging WHERE provider=$1 AND city_code=$2').run(...args);
            await db.prepare(`UPDATE bus_catalog_regions SET synced_at=now(),next_attempt_at=now()+interval '1 month',
              page=1,expected_total=NULL,last_error=NULL WHERE provider=$1 AND city_code=$2`).run(...args);
            console.log('Bus catalog synchronized:',region.provider,region.city_code||'busan',seen.count);
          });
        } catch(error) {
          const code=error instanceof ApiError?error.message:'BUS_CATALOG_SYNC_FAILED';
          await db.transaction(async()=>{
            await db.prepare('DELETE FROM bus_catalog_staging WHERE provider=$1 AND city_code=$2').run(...args);
            await db.prepare(`UPDATE bus_catalog_regions SET page=1,expected_total=NULL,last_error=$3,
              next_attempt_at=now()+interval '1 hour' WHERE provider=$1 AND city_code=$2`).run(...args,code);
          });
          console.error('Bus catalog sync failed:',region.provider,region.city_code||'busan',code);
        }
      }
    } finally {
      await db.prepare('SELECT pg_advisory_unlock(798231605)').get();
    }
  });
}

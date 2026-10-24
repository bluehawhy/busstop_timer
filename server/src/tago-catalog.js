import { ApiError } from './planner.js';

export function decodedKey(value) {
  if (!value?.trim()) throw new ApiError('BUS_PROVIDER_NOT_CONFIGURED',503);
  try { return /%[0-9a-f]{2}/i.test(value) ? decodeURIComponent(value.trim()) : value.trim(); }
  catch { throw new ApiError('BUS_PROVIDER_INVALID_KEY_ENCODING',503); }
}

export async function requestTago(service, operation, params, env = process.env) {
  const allowed = {ArvlInfoInqireService:['getCtyCodeList'],BusSttnInfoInqireService:['getCtyCodeList','getSttnNoList']};
  if (!allowed[service]?.includes(operation)) throw new ApiError('INVALID_TAGO_OPERATION');
  const url = new URL(`https://apis.data.go.kr/1613000/${service}/${operation}`);
  url.searchParams.set('serviceKey',decodedKey(env.TAGO_SERVICE_KEY));
  url.searchParams.set('_type','json');
  for (const [key,value] of Object.entries(params)) url.searchParams.set(key,String(value));
  let payload;
  try {
    const response = await fetch(url,{signal:AbortSignal.timeout(8000)});
    if (!response.ok) throw new Error();
    const reader=response.body.getReader(),chunks=[];
    let bytes=0;
    try {
      while (true) {
        const {done,value}=await reader.read();
        if (done) break;
        bytes+=value.byteLength;
        if(bytes>2*1024*1024) {await reader.cancel();throw new Error();}
        chunks.push(value);
      }
    } finally {reader.releaseLock();}
    payload=JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {throw new ApiError('BUS_PROVIDER_UNAVAILABLE',502);}
  if (String(payload?.response?.header?.resultCode)!=='00') throw new ApiError('BUS_PROVIDER_REJECTED_REQUEST',502);
  const body=payload.response.body,item=body?.items?.item;
  if(!body || (item!=null && typeof item!=='object')) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
  const rows=item ? Array.isArray(item)?item:[item] : [];
  const total=body.totalCount;
  if(rows.length>1000 || (total!=null && (!/^\d+$/.test(String(total)) || Number(total)<rows.length)) ||
    (!rows.length && Number(total)>0) || (total==null && !Object.hasOwn(body,'items'))) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
  return {rows,totalCount:total==null?rows.length:Number(total)};
}

// Intersection: station search support alone does not guarantee arrival support.
export async function tagoCities(env = process.env, reserve = async()=>{}) {
  await reserve();
  const arrivals=await requestTago('ArvlInfoInqireService','getCtyCodeList',{},env);
  await reserve();
  const stops=await requestTago('BusSttnInfoInqireService','getCtyCodeList',{},env);
  if(arrivals.rows.length!==arrivals.totalCount || stops.rows.length!==stops.totalCount) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE',502);
  const ids=new Set(stops.rows.map(row=>String(row.citycode)));
  return arrivals.rows.filter(row=>ids.has(String(row.citycode))).map(row=>{
    if(!/^\d{1,8}$/.test(String(row.citycode))||typeof row.cityname!=='string'||!row.cityname) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
    return {provider:'tago',cityCode:String(row.citycode),name:row.cityname};
  });
}

export async function searchTagoStops({query,arsNo,cityCode,page=1},env=process.env) {
  if(!/^\d{1,8}$/.test(cityCode??'')) throw new ApiError('CITY_CODE_REQUIRED');
  const result=await requestTago('BusSttnInfoInqireService','getSttnNoList',{
    cityCode,pageNo:page,numOfRows:100,...(arsNo?{nodeNo:arsNo}:{nodeNm:query})},env);
  const stops=result.rows.map(row=>{
    const latitude=Number(row.gpslati),longitude=Number(row.gpslong);
    if(!/^[\w-]{1,100}$/.test(row.nodeid??'')||!row.nodenm||
      row.gpslati==null||row.gpslati===''||row.gpslong==null||row.gpslong===''||
      !Number.isFinite(latitude)||Math.abs(latitude)>90||!Number.isFinite(longitude)||Math.abs(longitude)>180) throw new ApiError('BUS_PROVIDER_INVALID_STOP',502);
    return {id:`tago-${cityCode}-${row.nodeid}`,name:String(row.nodenm).slice(0,199),latitude,longitude,
      providerStopId:row.nodeid,cityCode,arsNo:row.nodeno==null?null:String(row.nodeno)};
  });
  return {stops,totalCount:result.totalCount,page,pageSize:100};
}

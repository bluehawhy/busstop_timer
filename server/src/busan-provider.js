import { XMLParser, XMLValidator } from 'fast-xml-parser';
import { ApiError } from './planner.js';

const BASE = 'https://apis.data.go.kr/6260000/BusanBIMS/';
const parser = new XMLParser({ignoreAttributes:true,parseTagValue:false,trimValues:true});
const numeric = value => typeof value === 'string' && /^\d+(\.\d+)?$/.test(value);
const id = value => typeof value === 'string' && /^\d{1,20}$/.test(value);

function serviceKey(env) {
  const value = (env.BUSAN_SERVICE_KEY ?? '').trim();
  if (!value) throw new ApiError('BUS_PROVIDER_NOT_CONFIGURED',503);
  // The portal may show either encoded or decoded keys. Decode exactly once.
  try { return /%[0-9a-f]{2}/i.test(value) ? decodeURIComponent(value) : value; }
  catch { throw new ApiError('BUS_PROVIDER_INVALID_KEY_ENCODING',503); }
}

export async function requestBusan(operation, params, env = process.env) {
  if (!['busStopList','stopArrByBstopid'].includes(operation)) throw new ApiError('INVALID_BUSAN_OPERATION');
  const url = new URL(operation,BASE);
  url.searchParams.set('serviceKey',serviceKey(env));
  for(const [key,value] of Object.entries(params)) url.searchParams.set(key,String(value));
  let xml,httpOK;
  try {
    const response = await fetch(url,{signal:AbortSignal.timeout(8000)});
    httpOK=response.ok;
    // Bound parsed XML and reject custom entities/DTDs.
    const reader=response.body.getReader(),chunks=[];
    let bytes=0;
    try {
      while(true) {
        const {done,value}=await reader.read();
        if(done) break;
        bytes+=value.byteLength;
        if(bytes>2*1024*1024) {await reader.cancel();throw new Error();}
        chunks.push(value);
      }
    } finally {reader.releaseLock();}
    xml=Buffer.concat(chunks).toString('utf8');
  } catch {throw new ApiError('BUS_PROVIDER_UNAVAILABLE',502);}
  if(/<!DOCTYPE|<!ENTITY/i.test(xml)||XMLValidator.validate(xml)!==true) throw new ApiError('BUS_PROVIDER_INVALID_XML',502);
  let document;
  try {document=parser.parse(xml);} catch {throw new ApiError('BUS_PROVIDER_INVALID_XML',502);}
  const response=document.response;
  const code=response?.header?.resultCode ?? document.OpenAPI_ServiceResponse?.cmmMsgHeader?.returnReasonCode;
  if(!httpOK || code!=='00') {
    const suffix=typeof code==='string' && /^\d{1,3}$/.test(code) ? `_${code}` : '';
    throw new ApiError(`BUS_PROVIDER_REJECTED_REQUEST${suffix}`,502);
  }
  if(!response.body || typeof response.body!=='object') throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
  const body=response.body;
  if(!Object.hasOwn(body,'items') && body.totalCount!=='0') throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
  const item=body.items?.item;
  const rows=item ? Array.isArray(item)?item:[item] : [];
  if(rows.length>1000) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
  if(body.totalCount!==undefined && (!numeric(body.totalCount)||Number(body.totalCount)<rows.length)) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
  if(!rows.length && body.totalCount!==undefined && Number(body.totalCount)>0) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE',502);
  return {rows,totalCount:body.totalCount===undefined ? null:Number(body.totalCount)};
}

export async function searchBusanStops({query,arsNo,page=1}, env = process.env) {
  const result=await requestBusan('busStopList',{pageNo:page,numOfRows:100,...(arsNo?{arsno:arsNo}:{bstopnm:query})},env);
  const stops=result.rows.map(row=>{
    // Village-bus stops can omit the public ARS number; bstopid remains required.
    const arsNo=row.arsno==null||row.arsno==='' ? null:row.arsno;
    if(!id(row.bstopid)||!row.bstopnm||!numeric(row.gpsx)||!numeric(row.gpsy)||
      Number(row.gpsx)>180||Number(row.gpsy)>90||Number(row.gpsy)<-90||(arsNo!==null&&(typeof arsNo!=='string'||!/^\d{1,5}$/.test(arsNo)))) throw new ApiError('BUS_PROVIDER_INVALID_STOP',502);
    return {id:`busan-${row.bstopid}`,name:row.bstopnm.slice(0,199),latitude:Number(row.gpsy),longitude:Number(row.gpsx),
      providerStopId:row.bstopid,arsNo:arsNo===null?null:arsNo.padStart(5,'0')};
  });
  return {stops,totalCount:result.totalCount,page,pageSize:100};
}

export async function fetchBusanArrivals(stop, env = process.env) {
  if(!id(stop.provider_stop_id)) throw new ApiError('STOP_PROVIDER_MAPPING_REQUIRED',409);
  const {rows,totalCount}=await requestBusan('stopArrByBstopid',{bstopid:stop.provider_stop_id},env);
  // This operation is not paginated. Never train on an incomplete feed.
  if(totalCount!==null&&totalCount!==rows.length) throw new ApiError('BUS_PROVIDER_INCOMPLETE_RESPONSE',502);
  const fetchedAt=new Date().toISOString(),arrivals=[],routes=new Map();
  for(const row of rows) {
    if(!id(row.lineid)||String(row.bstopid)!==stop.provider_stop_id||!row.lineno) throw new ApiError('BUS_PROVIDER_INVALID_RESPONSE',502);
    const routeId=`busan-${row.lineid}`,routeName=String(row.lineno).slice(0,199);
    routes.set(routeId,{routeId,routeName,direction:null,providerRouteId:row.lineid});
    for(const rank of [1,2]) {
      const value=row[`min${rank}`];
      // 운행대기/정보없음 and absent fields must never become zero-minute arrivals.
      if(value===undefined||value===''||['운행대기','정보없음','운행종료','-'].includes(value)) continue;
      if(!numeric(value)) continue;
      const etaSeconds=Math.round(Number(value)*60);
      if(etaSeconds>14400) continue;
      const remaining=row[`station${rank}`];
      arrivals.push({stopId:stop.id,routeId,routeName,etaSeconds,observedAt:fetchedAt,
        expectedAt:new Date(Date.parse(fetchedAt)+etaSeconds*1000).toISOString(),
        remainingStops:numeric(remaining)?Number(remaining):null,arrivalSequence:rank});
    }
  }
  return {arrivals:arrivals.sort((a,b)=>a.etaSeconds-b.etaSeconds),routes:[...routes.values()],fetchedAt,provider:'busan'};
}

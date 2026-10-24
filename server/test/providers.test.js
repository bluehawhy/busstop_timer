import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchBusArrivals, providerKey, stopEnvironment } from '../src/bus-provider.js';
import { fetchBusanArrivals, searchBusanStops } from '../src/busan-provider.js';
import { tagoCities, searchTagoStops } from '../src/tago-catalog.js';
import { busApi } from '../src/bus-api.js';
const env={BUS_PROVIDER:'auto',BUSAN_SERVICE_KEY:'a%2Bb%3D',TAGO_SERVICE_KEY:'a%2Bb%3D'};
const busan={id:'busan-123',provider_stop_id:'123',provider:'busan'};
const tago={id:'tago-25-DJB1',provider_stop_id:'DJB1',provider_city_code:'25',provider:'tago'};
const xml=(rows,total=rows.length)=>new Response(`<response><header><resultCode>00</resultCode></header><body><items>${rows.map(r=>`<item>${Object.entries(r).map(([k,v])=>`<${k}>${v}</${k}>`).join('')}</item>`).join('')}</items><totalCount>${total}</totalCount></body></response>`);
const json=(rows,total=rows.length)=>Response.json({response:{header:{resultCode:'00'},body:{items:rows.length?{item:rows.length===1?rows[0]:rows}:'',totalCount:total}}});
function mock(t,fn) {t.mock.method(globalThis,'fetch',fn);}
test('mixed providers use each stop identity',()=>{
  assert.equal(stopEnvironment(busan,env).BUS_PROVIDER,'busan');
  assert.equal(stopEnvironment(tago,env).BUS_PROVIDER,'tago');
  assert.equal(env.BUS_PROVIDER,'auto');
  assert.notEqual(providerKey(tago,env),providerKey({...tago,provider_city_code:'26'},env));
});
test('Busan uses bstopid, decodes key once, converts minutes and preserves ranks',async t=>{
  mock(t,async url=>{
    assert.equal(url.pathname,'/6260000/BusanBIMS/stopArrByBstopid');
    assert.equal(url.searchParams.get('bstopid'),'123');
    assert.equal(url.searchParams.get('cityCode'),null);
    assert.equal(url.searchParams.get('serviceKey'),'a+b=');
    return xml([{bstopid:'123',lineid:'10',lineno:'179',min1:'2',min2:'5'}]);
  });
  assert.deepEqual((await fetchBusArrivals(busan,env)).arrivals.map(r=>[r.etaSeconds,r.arrivalSequence]),[[120,1],[300,2]]);
});
test('waiting first Busan vehicle never becomes zero or changes second rank',async t=>{
  mock(t,async()=>xml([{bstopid:'123',lineid:'10',lineno:'179',min1:'운행대기',min2:'5'}]));
  const feed=await fetchBusanArrivals(busan,env);
  assert.equal(feed.arrivals.length,1);assert.equal(feed.arrivals[0].arrivalSequence,2);
});
test('Busan search preserves leading ARS zero and coordinate order',async t=>{
  mock(t,async url=>{
    assert.equal(url.searchParams.get('arsno'),'01234');
    return xml([{bstopid:'123',bstopnm:'부산역',arsno:'01234',gpsx:'129.04',gpsy:'35.11'}]);
  });
  const r=await searchBusanStops({arsNo:'01234'},env);
  assert.equal(r.stops[0].latitude,35.11);assert.equal(r.stops[0].arsNo,'01234');
});
test('TAGO uses cityCode/nodeId and seconds',async t=>{
  mock(t,async url=>{
    assert.equal(url.searchParams.get('cityCode'),'25');assert.equal(url.searchParams.get('nodeId'),'DJB1');
    assert.equal(url.searchParams.get('serviceKey'),'a+b=');
    return json([{nodeid:'DJB1',routeid:'R1',routeno:'101',arrtime:75}]);
  });
  const r=await fetchBusArrivals(tago,env);
  assert.equal(r.arrivals[0].etaSeconds,75);assert.equal(r.arrivals[0].routeId,'tago-25-R1');
});
for(const cityCode of ['25','26','37010']) test(`TAGO search isolates city ${cityCode}`,async t=>{
  mock(t,async url=>{
    assert.equal(url.searchParams.get('cityCode'),cityCode);assert.equal(url.searchParams.get('nodeNm'),'시청');
    return json([{nodeid:'NODE1',nodenm:'시청',gpslati:35.1,gpslong:129.1,nodeno:'00123'}]);
  });
  assert.equal((await searchTagoStops({cityCode,query:'시청'},env)).stops[0].id,`tago-${cityCode}-NODE1`);
});
test('city list intersects station and arrival support, counting both calls',async t=>{
  let reserved=0;
  mock(t,async url=>url.pathname.includes('Arvl')?json([{citycode:25,cityname:'대전'},{citycode:26,cityname:'울산'}]):json([{citycode:25,cityname:'대전'}]));
  assert.deepEqual(await tagoCities(env,async()=>{reserved++;}),[{provider:'tago',cityCode:'25',name:'대전'}]);
  assert.equal(reserved,2);
});
test('TAGO empty feed stays empty',async t=>{
  mock(t,async()=>json([]));assert.deepEqual((await fetchBusArrivals(tago,env)).arrivals,[]);
});
for(const [name,response] of [
  ['partial',()=>json([{nodeid:'DJB1',routeid:'R1',arrtime:10}],2)],
  ['wrong stop',()=>json([{nodeid:'OTHER',routeid:'R1',arrtime:10}])],
  ['negative ETA',()=>json([{nodeid:'DJB1',routeid:'R1',arrtime:-1}])],
  ['missing ETA',()=>json([{nodeid:'DJB1',routeid:'R1'}])],
  ['HTTP failure',()=>new Response('',{status:503})],
  ['invalid JSON',()=>new Response('<error/>')],
]) test(`TAGO rejects ${name}`,async t=>{
  mock(t,async()=>response());await assert.rejects(fetchBusArrivals(tago,env),/BUS_PROVIDER_/);
});
test('Busan rejects XML entity declarations',async t=>{
  mock(t,async()=>new Response('<!DOCTYPE response [<!ENTITY x "x">]><response/>'));
  await assert.rejects(fetchBusanArrivals(busan,env),/INVALID_XML/);
});
test('missing mapping/key fails before HTTP',async t=>{
  mock(t,async()=>assert.fail('must not fetch'));
  await assert.rejects(fetchBusArrivals({...tago,provider_city_code:null},env),/MAPPING_REQUIRED/);
  await assert.rejects(fetchBusArrivals(busan,{BUS_PROVIDER:'auto'}),/NOT_CONFIGURED/);
});
test('search rejects unsupported city and persists selected provider',async t=>{
  t.mock.property(process,'env',{...process.env,...env});
  let saved;
  const db={prepare(sql){return {get:async()=>({requests:1}),run:async(...args)=>{if(sql.includes('INSERT INTO stops'))saved=args;}};},transaction:async fn=>fn()};
  mock(t,async url=>url.pathname.includes('getCtyCodeList')?json([{citycode:25,cityname:'대전'}]):json([{nodeid:'DJB1',nodenm:'시청',gpslati:36.3,gpslong:127.4}]));
  const call=q=>busApi(new Request(`https://example.com/api/bus/stops/search?${q}`),db,'user',false,'/api/bus/stops/search');
  await assert.rejects(call('provider=tago&cityCode=11&q=시청'),/UNSUPPORTED_CITY/);
  assert.equal((await (await call('provider=tago&cityCode=25&q=시청')).json()).provider,'tago');
  assert.equal(saved[6],'25');assert.equal(saved[7],'tago');
});

test('different station and arrival keys reach their own city-list APIs',async t=>{
  const split={...env,TAGO_STATION_SERVICE_KEY:'station%2Bkey',TAGO_ARRIVAL_SERVICE_KEY:'arrival%2Bkey'};
  mock(t,async url=>{
    assert.equal(url.searchParams.get('serviceKey'),url.pathname.includes('Arvl')?'arrival+key':'station+key');
    return json([{citycode:25,cityname:'대전'}]);
  });
  assert.equal((await tagoCities(split)).length,1);
});
test('station search and arrival feed each prefer their specific key',async t=>{
  const split={...env,TAGO_STATION_SERVICE_KEY:'station',TAGO_ARRIVAL_SERVICE_KEY:'arrival'};
  mock(t,async url=>{
    const arrival=url.pathname.includes('Arvl');
    assert.equal(url.searchParams.get('serviceKey'),arrival?'arrival':'station');
    return arrival?json([{nodeid:'DJB1',routeid:'R1',arrtime:75}]):json([{nodeid:'DJB1',nodenm:'시청',gpslati:36.3,gpslong:127.4}]);
  });
  await searchTagoStops({cityCode:'25',query:'시청'},split);
  await fetchBusArrivals(tago,split);
});

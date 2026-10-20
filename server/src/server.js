import { createServer } from 'node:http';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { resolve, extname, sep } from 'node:path';
import { openDatabase, legacyDatabase } from './database.js';
import { journeyApi, evaluateSession } from './journeys.js';
import legacy from './index.js';
import { busApi } from './bus-api.js';
import { collectSavedArrivals } from './bus-history.js';
import { ApiError } from './planner.js';

const db=await openDatabase();
const hash = value => createHash('sha256').update(value).digest('hex');
if(process.argv[2]==='create-device') {
  const created=await db.transaction(async()=>{
  const user=process.argv[3]??randomUUID(), token=randomBytes(32).toString('base64url');
  (await db.prepare(`INSERT INTO users(id) VALUES($1) ON CONFLICT DO NOTHING`).run(user));
  (await db.prepare(`INSERT INTO api_devices(token_hash,user_id,label) VALUES($1,$2,$3)`).run(hash(token),user,process.argv[4]??'phone'));
  return {userId:user,token};
  });
  console.log(JSON.stringify(created));
  await db.close();process.exit(0);
}
const base=(process.env.BASE_PATH??'/').replace(/\/$/,'');
const staticRoot=resolve(process.env.WEB_ROOT??'../build/web');
const equal=(a,b)=>Buffer.byteLength(a)===Buffer.byteLength(b)&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
const mime={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.css':'text/css','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2'};
const allowed=(process.env.ALLOWED_ORIGINS??'https://bustimer.bluewaikiki.top').split(',').map(v=>v.trim());
const server=createServer(async(req,res)=>{
  try {
    const url=new URL(req.url,'http://localhost');
    if(url.pathname===base){res.writeHead(308,{location:`${base}/`});res.end();return;}
    if(!url.pathname.startsWith(`${base}/`)) {res.writeHead(404);res.end();return;}
    const path=url.pathname.slice(base.length);
    if(!path.startsWith('/api/')&&path!=='/health') {
      let file=resolve(staticRoot,`.${decodeURIComponent(path)}`);
      if(!file.startsWith(staticRoot+sep)&&file!==staticRoot) throw new ApiError('NOT_FOUND',404);
      if(file===staticRoot||!existsSync(file)||statSync(file).isDirectory()) {
        // SPA routes may fall back, missing assets must remain 404.
        if(extname(path)) throw new ApiError('NOT_FOUND',404);
        file=resolve(staticRoot,'index.html');
      }
      if(!existsSync(file)) throw new ApiError('WEB_BUILD_NOT_FOUND',404);
      res.writeHead(200,{'content-type':mime[extname(file)]??'application/octet-stream',
        'cache-control':file.endsWith('index.html')?'no-store':'public,max-age=300'});res.end(readFileSync(file));return;
    }
    const origin=req.headers.origin;
    if(origin&&!allowed.includes(origin)) throw new ApiError('FORBIDDEN_ORIGIN',403);
    const cors=origin?{'access-control-allow-origin':origin,'vary':'Origin'}:{};
    if(req.method==='OPTIONS'){res.writeHead(204,{...cors,'access-control-allow-methods':'GET,POST,DELETE,OPTIONS','access-control-allow-headers':'Content-Type,Authorization'});res.end();return;}
    if(path==='/health'){await db.prepare('SELECT 1').get();res.writeHead(200,{'content-type':'application/json'});res.end('{"ok":true}');return;}
    await db.withConnection(async()=>{
    const bearer=(req.headers.authorization??'').replace(/^Bearer /,'');
    const admin=Boolean(process.env.API_BEARER_TOKEN)&&equal(bearer,process.env.API_BEARER_TOKEN);
    const device=bearer?(await db.prepare(`SELECT user_id FROM api_devices WHERE token_hash=$1`).get(hash(bearer))):null;
    if(!admin&&!device) throw new ApiError('UNAUTHORIZED',401);
    const chunks=[];let size=0;
    for await(const chunk of req){size+=chunk.length;if(size>4*1024*1024) throw new ApiError('BODY_TOO_LARGE',413);chunks.push(chunk);}
    const body=Buffer.concat(chunks);
    if(req.method==='POST') {
      const payload=JSON.parse(body.toString('utf8'));
      if(!payload || typeof payload!=='object' || Array.isArray(payload)) throw new ApiError('INVALID_JSON');
    }
    const request=new Request(`http://localhost${path}${url.search}`,{method:req.method,headers:req.headers,
      ...(['GET','HEAD'].includes(req.method)?{}:{body})});
    // New endpoints derive user ownership from a device token, never request userId.
    if(admin) await db.prepare('INSERT INTO users(id) VALUES($1) ON CONFLICT DO NOTHING').run('admin');
    let response=await busApi(request,db,device?.user_id??'admin',admin,path);
    if(!response) response=await journeyApi(request,db,device?.user_id??'admin',admin,path);
    if(!response&&admin) response=await legacy.fetch(request,{...process.env,DB:legacyDatabase(db)});
    if(!response) throw new ApiError('NOT_FOUND',404);
    const headers=Object.fromEntries(response.headers);
    delete headers['access-control-allow-origin'];
    res.writeHead(response.status,{...headers,...cors,'cache-control':'no-store'});
    res.end(Buffer.from(await response.arrayBuffer()));
    });
  }catch(e){
    const status=e instanceof ApiError?e.status:e instanceof SyntaxError?400:500;
    if(status===500) console.error('API error:',e.message);
    if(!res.headersSent) res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'});
    res.end(JSON.stringify({error:status===500?'INTERNAL_ERROR':e.message}));
  }
});
server.requestTimeout=15000;
server.listen(Number(process.env.PORT??18082),process.env.HOST??'127.0.0.1',()=>console.log(`Bus Timer listening at ${base}/`));
// Evaluate active sessions even when clients are not currently polling. No remote push is claimed.
let evaluating=false;
const timer=setInterval(async()=>{
  if(evaluating) return;
  evaluating=true;
  try{
    const sessions=await db.prepare("SELECT * FROM journey_sessions WHERE status IN ('waiting','riding','transfer')").all();
    for(const session of sessions) await evaluateSession(db,session);
    await db.prepare('DELETE FROM journey_options WHERE expires_at<$1').run(new Date().toISOString());
  }catch(e){console.error('Journey evaluation failed:',e.message);}
  finally{evaluating=false;}
},15000);
let collecting=false;
async function collect() {
  if(collecting) return;
  collecting=true;
  try { await collectSavedArrivals(db); }
  catch(error) { console.error('Bus collection failed:',error.code ?? 'UNKNOWN'); }
  finally { collecting=false; }
}
let pendingCollection=collect();
const busTimer=setInterval(()=>{if(!collecting) pendingCollection=collect();},60000);
let stopping=false;
function shutdown(){
  if(stopping) return;
  stopping=true;clearInterval(timer);clearInterval(busTimer);
  server.close(async()=>{await pendingCollection;await db.close();});
}
process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);

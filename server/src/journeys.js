import { randomUUID } from 'node:crypto';
import { ApiError, validateSearch, plan, loadRides } from './planner.js';
import { importCatalog } from './catalog.js';
const json = (value,status=200) => Response.json(value,{status});
const iso = n => new Date(n).toISOString();
const parse = value => JSON.parse(value);
function ownedSession(db, user, id) {
  const row = db.prepare('SELECT * FROM journey_sessions WHERE id=? AND user_id=?').get(id,user);
  if (!row) throw new ApiError('SESSION_NOT_FOUND',404);
  return row;
}
const sessionView = row => ({id:row.id,status:row.status,currentLeg:row.current_leg,revision:row.revision,option:parse(row.option_json)});

export function evaluateSession(db, session, now = Date.now()) {
  if (!['waiting','riding','transfer'].includes(session.status)) return;
  const option = parse(session.option_json);
  const live = loadRides(db,now,now-86400000,now+86400000);
  const old = JSON.stringify(option);
  for (let i=session.current_leg; i<option.legs.length; i++) {
    const leg=option.legs[i];
    const current=(live.get(leg.fromStopId)??[]).find(r=>r.vehicleKey===leg.vehicleKey&&r.toStopId===leg.toStopId);
    if (!current) {
      db.prepare("UPDATE journey_sessions SET status='disrupted',revision=revision+1 WHERE id=?").run(session.id);
      return;
    }
    Object.assign(leg,current);
    if (i>session.current_leg || (i===session.current_leg&&session.status!=='riding')) {
      const previous=i>0?Date.parse(option.legs[i-1].arrivalAt):now;
      const ready=previous+(leg.walkSeconds+leg.bufferSeconds)*1000;
      // While waiting for a transfer, the user has explicitly confirmed arrival.
      const minimum=i===session.current_leg&&session.status==='transfer'?now:ready;
      if (Date.parse(leg.departureAt)<minimum) {
        db.prepare("UPDATE journey_sessions SET status='disrupted',revision=revision+1 WHERE id=?").run(session.id);
        return;
      }
    }
  }
  option.arrivalAt=option.legs.at(-1).arrivalAt;
  option.durationSeconds=(Date.parse(option.arrivalAt)-Date.parse(option.departureAt))/1000;
  if (JSON.stringify(option)!==old) db.prepare('UPDATE journey_sessions SET option_json=?,revision=revision+1 WHERE id=?').run(JSON.stringify(option),session.id);
  const target=session.status==='riding'?session.current_leg+1:session.current_leg;
  const leg=option.legs[target];
  if (!leg) return;
  const seconds=(Date.parse(leg.departureAt)-now)/1000;
  if (seconds<0||seconds>300) return;
  const event={id:randomUUID(),sessionId:session.id,legIndex:target,vehicleKey:leg.vehicleKey,
    routeName:leg.routeName,stopName:leg.fromStopName,direction:leg.direction,
    departureAt:leg.departureAt,etaMinutes:Math.ceil(seconds/60),basis:leg.basis,
    kind:target===0?'boarding':'transfer'};
  db.prepare(`INSERT OR IGNORE INTO journey_alerts(id,session_id,leg_index,vehicle_key,kind,body_json)
    VALUES(?,?,?,?,?,?)`).run(event.id,session.id,target,leg.vehicleKey,event.kind,JSON.stringify(event));
}

export async function journeyApi(request, db, user, admin, path) {
  const url=new URL(request.url), method=request.method;
  if (path==='/api/catalog'&&method==='POST') {
    if (!admin) throw new ApiError('FORBIDDEN',403);
    return json(importCatalog(db,await request.json()));
  }
  if (path==='/api/journey-stops'&&method==='GET') {
    const q=(url.searchParams.get('q')??'').slice(0,100);
    return json({stops:db.prepare('SELECT id,name FROM stops WHERE instr(lower(name),lower(?))>0 OR id=? ORDER BY name LIMIT 100').all(q,q)});
  }
  if (path==='/api/journeys/search'&&method==='POST') {
    const search=validateSearch(await request.json());
    for (const stop of [search.originStopId,search.destinationStopId]) if(!db.prepare('SELECT id FROM stops WHERE id=?').get(stop)) throw new ApiError('STOP_NOT_FOUND',404);
    const comparisons=plan(db,search);
    db.exec('BEGIN IMMEDIATE');
    try {
      db.prepare('DELETE FROM journey_options WHERE expires_at<?').run(iso(Date.now()));
      for (const comparison of comparisons) for (const option of comparison.options) {
        option.id=randomUUID();
        db.prepare('INSERT INTO journey_options VALUES(?,?,?,?,?)').run(option.id,user,JSON.stringify({...search,departureAt:comparison.departureAt,compareCount:1}),JSON.stringify(option),iso(Date.now()+600000));
      }
      db.exec('COMMIT');
    }catch(e){db.exec('ROLLBACK');throw e;}
    return json({comparisons,generatedAt:iso(Date.now()),dataStatus:comparisons.some(c=>c.options.length)?'available':'no_usable_connections'});
  }
  if(path==='/api/saved-journeys'&&method==='GET') return json({journeys:db.prepare('SELECT * FROM saved_journeys WHERE user_id=? ORDER BY created_at DESC').all(user)});
  if(path==='/api/saved-journeys'&&method==='POST') {
    const b=await request.json();
    if(typeof b.name!=='string'||!b.name.trim()||b.name.length>100||!Array.isArray(b.weekdays)||!b.weekdays.length||
      b.weekdays.some(d=>!Number.isInteger(d)||d<1||d>7)||!/^([01]\d|2[0-3]):[0-5]\d$/.test(b.departureTime)) throw new ApiError('INVALID_SAVED_JOURNEY');
    const search=validateSearch({...b,departureAt:iso(Date.now())});
    const id=randomUUID();
    db.prepare('INSERT INTO saved_journeys(id,user_id,name,origin_stop_id,destination_stop_id,weekdays,departure_time) VALUES(?,?,?,?,?,?,?)')
      .run(id,user,b.name.trim(),search.originStopId,search.destinationStopId,JSON.stringify(b.weekdays),b.departureTime);
    return json({id},201);
  }
  const saved=path.match(/^\/api\/saved-journeys\/([\w-]+)$/);
  if(saved&&method==='DELETE') {db.prepare('DELETE FROM saved_journeys WHERE id=? AND user_id=?').run(saved[1],user);return json({deleted:true});}
  if(path==='/api/journey-sessions'&&method==='GET') return json({sessions:db.prepare("SELECT * FROM journey_sessions WHERE user_id=? AND status NOT IN ('completed','cancelled') ORDER BY created_at DESC").all(user).map(sessionView)});
  if(path==='/api/journey-sessions'&&method==='POST') {
    const b=await request.json();
    const candidate=db.prepare('SELECT * FROM journey_options WHERE id=? AND user_id=? AND expires_at>?').get(b.optionId,user,iso(Date.now()));
    if(!candidate) throw new ApiError('OPTION_EXPIRED',409);
    const option=parse(candidate.option_json);
    if(Date.parse(option.legs[0].departureAt)<Date.now()) throw new ApiError('DEPARTURE_PASSED',409);
    const id=randomUUID();
    db.prepare("INSERT INTO journey_sessions(id,user_id,option_json,status) VALUES(?,?,?,'waiting')").run(id,user,candidate.option_json);
    return json(sessionView(ownedSession(db,user,id)),201);
  }
  const match=path.match(/^\/api\/journey-sessions\/([\w-]+)(?:\/(action|alerts|replan|ack))?$/);
  if(!match) return null;
  const session=ownedSession(db,user,match[1]);
  const action=match[2];
  if(!action&&method==='GET') {evaluateSession(db,session);return json(sessionView(ownedSession(db,user,session.id)));}
  if(action==='action'&&method==='POST') {
    const b=await request.json();
    if(b.revision!==session.revision) throw new ApiError('SESSION_CHANGED',409);
    let status=session.status,index=session.current_leg;
    if(b.action==='cancel'&&!['completed','cancelled'].includes(status)) status='cancelled';
    else if(b.action==='board'&&['waiting','transfer'].includes(status)) status='riding';
    else if(b.action==='alight'&&status==='riding') {
      index++;status=index>=parse(session.option_json).legs.length?'completed':'transfer';
    } else if(b.action==='missed'&&['waiting','transfer'].includes(status)) status='disrupted';
    else throw new ApiError('INVALID_TRANSITION',409);
    db.prepare('UPDATE journey_sessions SET status=?,current_leg=?,revision=revision+1 WHERE id=? AND revision=?').run(status,index,session.id,session.revision);
    // Old undelivered notifications are invalid after every explicit state transition.
    db.prepare('UPDATE journey_alerts SET acknowledged_at=CURRENT_TIMESTAMP WHERE session_id=? AND acknowledged_at IS NULL').run(session.id);
    return json(sessionView(ownedSession(db,user,session.id)));
  }
  if(action==='alerts'&&method==='GET') {
    evaluateSession(db,session);
    const fresh=ownedSession(db,user,session.id);
    if(!['waiting','riding','transfer'].includes(fresh.status)) return json({alerts:[],status:fresh.status});
    const legs=parse(fresh.option_json).legs;
    const target=fresh.status==='riding'?fresh.current_leg+1:fresh.current_leg;
    const alerts=db.prepare('SELECT body_json FROM journey_alerts WHERE session_id=? AND acknowledged_at IS NULL').all(session.id)
      .map(r=>parse(r.body_json)).filter(event=>{
        const leg=legs[event.legIndex];
        const remaining=leg?(Date.parse(leg.departureAt)-Date.now())/60000:-1;
        if(event.legIndex!==target||!leg||remaining<0||remaining>5) return false;
        Object.assign(event,{departureAt:leg.departureAt,etaMinutes:Math.ceil(remaining),basis:leg.basis});
        return true;
      });
    return json({alerts,status:fresh.status});
  }
  if(action==='ack'&&method==='POST') {
    const b=await request.json();if(!Array.isArray(b.ids)||b.ids.length>100||b.ids.some(v=>typeof v!=='string')) throw new ApiError('INVALID_ACK');
    for(const id of b.ids) db.prepare('UPDATE journey_alerts SET acknowledged_at=CURRENT_TIMESTAMP WHERE id=? AND session_id=?').run(id,session.id);
    return json({acknowledged:true});
  }
  if(action==='replan'&&method==='POST') {
    if(['completed','cancelled','riding'].includes(session.status)) throw new ApiError('REPLAN_REQUIRES_STOP',409);
    const option=parse(session.option_json),leg=option.legs[session.current_leg];
    const search=validateSearch({originStopId:leg.fromStopId,destinationStopId:option.legs.at(-1).toStopId,departureAt:iso(Date.now())});
    const comparisons=plan(db,search);
    for(const comparison of comparisons) for(const candidate of comparison.options) {
      candidate.id=randomUUID();
      db.prepare('INSERT INTO journey_options VALUES(?,?,?,?,?)').run(candidate.id,user,JSON.stringify(search),JSON.stringify(candidate),iso(Date.now()+600000));
    }
    return json({comparisons,previousSessionId:session.id});
  }
  return null;
}

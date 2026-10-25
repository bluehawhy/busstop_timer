import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import nodemailer from 'nodemailer';
import { authMailHtml } from './auth-mail.js';
import { ApiError } from './planner.js';

const hash = value => createHash('sha256').update(value).digest('hex');
const emailOf = body => {
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new ApiError('INVALID_EMAIL');
  return email;
};
function codeHash(token, email, challenge, code) {
  const key = process.env.AUTH_RATE_LIMIT_KEY ?? '';
  if (key.length < 32) throw new ApiError('AUTH_NOT_CONFIGURED',503);
  return createHmac('sha256',key).update(JSON.stringify([token,email,challenge,code])).digest('hex');
}
async function rate(db, key, limit, seconds) {
  const row = await db.prepare(`INSERT INTO auth_rate_limits(key,count,expires_at) VALUES($1,1,NOW()+$2*INTERVAL '1 second')
    ON CONFLICT(key) DO UPDATE SET count=CASE WHEN auth_rate_limits.expires_at<=NOW() THEN 1 ELSE auth_rate_limits.count+1 END,
    expires_at=CASE WHEN auth_rate_limits.expires_at<=NOW() THEN excluded.expires_at ELSE auth_rate_limits.expires_at END RETURNING count`).get(key,seconds);
  if(row.count>limit) throw new ApiError('AUTH_RATE_LIMITED',429);
}
async function sendMail(email,code,link) {
  const env=process.env;
  if(!env.AUTH_SMTP_HOST || !env.AUTH_SMTP_USERNAME || !env.AUTH_SMTP_PASSWORD || !env.AUTH_EMAIL_FROM) throw new ApiError('AUTH_MAIL_NOT_CONFIGURED',503);
  const mode=env.AUTH_SMTP_TLS_MODE??'starttls';
  if(!['ssl','starttls'].includes(mode)) throw new ApiError('AUTH_MAIL_NOT_CONFIGURED',503);
  const transport=nodemailer.createTransport({host:env.AUTH_SMTP_HOST,port:Number(env.AUTH_SMTP_PORT??(mode==='ssl'?465:587)),
    secure:mode==='ssl',requireTLS:true,auth:{user:env.AUTH_SMTP_USERNAME,pass:env.AUTH_SMTP_PASSWORD},
    connectionTimeout:10000,greetingTimeout:10000,socketTimeout:15000});
  try {
    await transport.sendMail({from:env.AUTH_EMAIL_FROM,to:email,subject:link?'버스타이머 이메일 인증 링크':'버스타이머 이메일 인증 숫자',
      text:link?`아래 링크에서 이메일 인증을 완료해주세요. 10분간 유효합니다.\n${link}`:`인증 숫자: ${code}\n버스타이머 화면에 입력해주세요. 10분 동안 유효하며 한 번만 사용할 수 있습니다.`,
      html:authMailHtml({code,link})});
  } catch { throw new ApiError('AUTH_MAIL_UNAVAILABLE',503); }
  finally { transport.close(); }
}

const authMode=()=>process.env.MAIL_AUTH_MODE?.toLowerCase()==='link'?'link':'otp';
async function finishLogin(db,source,tokenHash,email,challengeId,keepToken) {
  if(await db.prepare('SELECT email FROM email_accounts WHERE user_id=$1').get(source)) return {error:'IDENTITY_ALREADY_LINKED'};
  const account=await db.prepare('SELECT user_id FROM email_accounts WHERE email=$1').get(email);
  const user=account?.user_id??source;
  await db.prepare('SELECT id FROM users WHERE id=$1 FOR UPDATE').get(source);
  if(!account) await db.prepare('INSERT INTO email_accounts(email,user_id) VALUES($1,$2)').run(email,user);
  if(user!==source) {
    await db.prepare(`DELETE FROM subscriptions s USING subscriptions t WHERE s.user_id=$2 AND t.user_id=$1 AND s.stop_id=t.stop_id AND s.route_id=t.route_id`).run(user,source);
    await db.prepare('UPDATE subscriptions SET user_id=$1 WHERE user_id=$2').run(user,source);
    for(const table of ['saved_journeys','journey_options','journey_sessions']) await db.prepare(`UPDATE ${table} SET user_id=$1 WHERE user_id=$2`).run(user,source);
    await db.prepare('DELETE FROM subscriptions WHERE user_id=$1').run(source);
  }
  await db.prepare('UPDATE email_challenges SET used=true WHERE id=$1').run(challengeId);
  const token=keepToken?null:randomBytes(32).toString('base64url');
  await db.prepare('DELETE FROM api_devices WHERE user_id=$1 AND token_hash<>$2').run(source,tokenHash);
  const hours=Number(process.env.AUTH_SESSION_HOURS??6);
  const seconds=(Number.isFinite(hours)&&hours>0?Math.min(hours,8760):6)*3600;
  if(keepToken) {
    await db.prepare("UPDATE api_devices SET user_id=$1,label='email',expires_at=NOW()+$3*INTERVAL '1 second' WHERE token_hash=$2").run(user,tokenHash,seconds);
  } else {
    await db.prepare('DELETE FROM api_devices WHERE token_hash=$1').run(tokenHash);
    await db.prepare(`INSERT INTO api_devices(token_hash,user_id,label,expires_at) VALUES($1,$2,'email',NOW()+$3*INTERVAL '1 second')`).run(hash(token),user,seconds);
  }
  return {token,email};
}

export async function emailAuth(request,db,device,bearer,path,ip) {
  if(!path.startsWith('/api/auth/')) return null;
  const tokenHash=hash(bearer),method=request.method;
  if(path==='/api/auth/config'&&method==='GET') return Response.json({mailAuthMode:authMode()});
  if(path==='/api/auth/status'&&method==='GET') {
    const account=await db.prepare('SELECT email FROM email_accounts WHERE user_id=$1').get(device.user_id);
    return Response.json({email:account?.email??null});
  }
  if(path==='/api/auth/logout'&&method==='POST') {
    await db.prepare('DELETE FROM api_devices WHERE token_hash=$1').run(tokenHash);
    return Response.json({ok:true});
  }
  if(['/api/auth/email-otp','/api/auth/email-link'].includes(path)&&method==='POST') {
    const b=await request.json(),email=emailOf(b);
    const mode=authMode();
    if(path!==`/api/auth/email-${mode}`) throw new ApiError('AUTH_MODE_CHANGED',409);
    if(await db.prepare('SELECT email FROM email_accounts WHERE user_id=$1').get(device.user_id)) throw new ApiError('IDENTITY_ALREADY_LINKED',409);
    await rate(db,'send-ip:'+hash(ip),10,3600);
    await rate(db,'send-email:'+hash(email),10,3600);
    await rate(db,'send-session:'+tokenHash,1,60);
    const challengeId=randomBytes(16).toString('hex'),code=mode==='link'?randomBytes(32).toString('hex'):String(randomInt(1000000)).padStart(6,'0');
    let link;
    if(mode==='link') {
      try {
        const url=new URL(process.env.AUTH_EMAIL_LINK_URL);
        if(url.protocol!=='https:'||url.username||url.password||url.hash) throw new Error();
        url.searchParams.set('challengeId',challengeId);url.searchParams.set('token',code);link=url.href;
      } catch {throw new ApiError('AUTH_MAIL_NOT_CONFIGURED',503);}
    }
    const digest=codeHash(tokenHash,email,challengeId,code);
    await db.transaction(async()=>{
      await db.prepare('SELECT user_id FROM api_devices WHERE token_hash=$1 FOR UPDATE').get(tokenHash);
      await db.prepare('DELETE FROM email_challenges WHERE token_hash=$1 OR expires_at<NOW()').run(tokenHash);
      await db.prepare(`INSERT INTO email_challenges(id,token_hash,email,code_hash,mode,expires_at) VALUES($1,$2,$3,$4,$5,NOW()+INTERVAL '10 minutes')`).run(challengeId,tokenHash,email,digest,mode);
    });
    try {await sendMail(email,code,link);} catch(e) {
      await db.prepare('DELETE FROM email_challenges WHERE id=$1').run(challengeId);throw e;
    }
    return Response.json({challengeId,expiresInSeconds:600});
  }
  if(path==='/api/auth/email-otp/verify'&&method==='POST') {
    const b=await request.json(),email=emailOf(b);
    if(!/^[0-9]{6}$/.test(b.code??'')||!/^[a-f0-9]{32}$/.test(b.challengeId??'')) throw new ApiError('INVALID_OTP_INPUT');
    await rate(db,'verify-ip:'+hash(ip),30,600);
    await rate(db,'verify-session:'+tokenHash,5,600);
    const result=await db.transaction(async()=>{
      // Serialize verification and account migration, including different devices.
      await db.prepare('SELECT pg_advisory_xact_lock(hashtextextended($1,0))').get(email);
      const current=await db.prepare('SELECT user_id FROM api_devices WHERE token_hash=$1 FOR UPDATE').get(tokenHash);
      if(!current) return {error:'UNAUTHORIZED'};
      const row=await db.prepare('SELECT *,expires_at>NOW() AS valid FROM email_challenges WHERE id=$1 FOR UPDATE').get(b.challengeId);
      if(!row||row.mode!=='otp'||row.used||!row.valid||row.token_hash!==tokenHash||row.email!==email||row.attempts>=5) return {error:'INVALID_OR_EXPIRED_OTP'};
      const expected=codeHash(tokenHash,email,b.challengeId,b.code);
      if(!timingSafeEqual(Buffer.from(expected),Buffer.from(row.code_hash))) {
        await db.prepare('UPDATE email_challenges SET attempts=attempts+1 WHERE id=$1').run(row.id);
        return {error:'INVALID_OR_EXPIRED_OTP'};
      }
      return finishLogin(db,current.user_id,tokenHash,email,row.id,false);
    });
    if(result.error) throw new ApiError(result.error,result.error==='UNAUTHORIZED'?401:400);
    return Response.json(result);
  }
  return null;
}

const escapeHtml = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
function landing(content,status=200) {
  const nonce=randomBytes(18).toString('base64');
  return new Response(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>버스타이머 이메일 인증</title></head><body><h1>버스타이머 이메일 인증</h1>${content}<script nonce="${nonce}">if(document.querySelector('[data-complete]')){window.close();}</script></body></html>`,{status,headers:{
    'content-type':'text/html; charset=utf-8','cache-control':'no-store','referrer-policy':'no-referrer',
    'content-security-policy':`default-src 'none'; script-src 'nonce-${nonce}'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`,
    'x-content-type-options':'nosniff','x-frame-options':'DENY',
  }});
}
// GET only presents confirmation; mail scanners cannot consume a login link.
export async function emailLinkLanding(request,db) {
  const url=new URL(request.url);
  const data=request.method==='POST'?new URLSearchParams(await request.text()):url.searchParams;
  const id=data.get('challengeId')??'',secret=data.get('token')??'';
  if(!/^[a-f0-9]{32}$/.test(id)||!/^[a-f0-9]{64}$/.test(secret)) return landing('<p>잘못된 인증 링크입니다.</p>',400);
  if(request.method==='GET') return landing(`<p>아래 버튼을 눌러 인증을 완료해주세요.</p><form method="post" action="${escapeHtml(url.pathname)}"><input type="hidden" name="challengeId" value="${id}"><input type="hidden" name="token" value="${secret}"><button type="submit">이메일 인증 완료하기</button></form>`);
  if(request.method!=='POST') return landing('<p>지원하지 않는 요청입니다.</p>',405);
  const initial=await db.prepare('SELECT email,token_hash FROM email_challenges WHERE id=$1').get(id);
  if(!initial) return landing('<p>인증 링크가 만료되었습니다. 앱에서 다시 요청해주세요.</p>',400);
  const result=await db.transaction(async()=>{
    await db.prepare('SELECT pg_advisory_xact_lock(hashtextextended($1,0))').get(initial.email);
    const device=await db.prepare('SELECT user_id FROM api_devices WHERE token_hash=$1 AND (expires_at IS NULL OR expires_at>NOW()) FOR UPDATE').get(initial.token_hash);
    const row=await db.prepare('SELECT *,expires_at>NOW() AS valid FROM email_challenges WHERE id=$1 FOR UPDATE').get(id);
    if(!device||!row||row.used||!row.valid||row.mode!=='link') return {error:true};
    const digest=codeHash(row.token_hash,row.email,id,secret);
    if(!timingSafeEqual(Buffer.from(digest),Buffer.from(row.code_hash))) return {error:true};
    return finishLogin(db,device.user_id,row.token_hash,row.email,id,true);
  });
  return result.error?landing('<p>인증할 수 없는 링크입니다. 앱에서 다시 요청해주세요.</p>',400):landing('<p data-complete>인증이 완료되었습니다. 이 창을 닫고 인증을 요청한 버스타이머 화면으로 돌아가세요.</p>');
}

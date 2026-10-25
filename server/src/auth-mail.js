const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
// Table layout and inline styles keep the web palette readable in mobile mail clients.
export function authMailHtml({code,link}) {
  const action=link
    ? `<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" bgcolor="#08746D" style="border-radius:18px"><a href="${escape(link)}" style="display:block;padding:19px 16px;color:#ffffff;text-decoration:none;font-size:17px;font-weight:bold;line-height:24px">이메일 인증하기</a></td></tr></table>`
    : `<div style="padding:24px 12px;background:#EDF4F2;border:1px solid #DCE8E5;border-radius:18px;text-align:center;font-size:34px;font-weight:bold;letter-spacing:7px;color:#07524E">${escape(code)}</div>`;
  const fallback=link?`<p style="margin:24px 0 8px;font-size:12px;line-height:20px;color:#718096">버튼이 작동하지 않으면 아래 주소를 브라우저에 붙여넣어주세요.</p><p style="margin:0;font-size:12px;line-height:20px;word-break:break-all"><a href="${escape(link)}" style="color:#08746D">${escape(link)}</a></p>`:'';
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>버스타이머 이메일 인증</title></head>
<body style="margin:0;padding:0;background:#FFFCF6;color:#112B46;font-family:Pretendard,-apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Malgun Gothic',Arial,sans-serif">
<div style="display:none;max-height:0;overflow:hidden">버스타이머 ${link?'인증 링크를 눌러':'6자리 인증번호로'} 이메일 인증을 완료해주세요.</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" bgcolor="#FFFCF6"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px"><tr><td style="padding:0 8px 22px;font-size:20px;font-weight:bold;color:#08746D">버스타이머</td></tr>
<tr><td bgcolor="#FFFFFF" style="padding:32px 24px;border:1px solid #E8E7E1;border-radius:24px">
<p style="margin:0 0 12px;font-size:12px;font-weight:bold;letter-spacing:1px;color:#08746D">매일의 이동을 가볍게</p>
<h1 style="margin:0 0 14px;font-size:26px;line-height:36px;letter-spacing:-1px;color:#112B46">이메일을 인증해주세요</h1>
<p style="margin:0 0 28px;font-size:15px;line-height:26px;color:#718096">${link?'아래 버튼을 눌러 인증을 완료해주세요.':'인증을 요청한 버스타이머 화면에<br>아래 6자리 숫자를 입력해주세요.'}<br>저장한 버스와 경로를 다른 기기에서도 이어볼 수 있어요.</p>
${action}
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:24px"><tr><td bgcolor="#EDF4F2" style="padding:16px;border-radius:14px;font-size:13px;line-height:23px;color:#536C70">• ${link?'인증 링크':'인증번호'}는 <strong>10분 동안</strong> 유효하며 한 번만 사용할 수 있어요.<br>• 새 인증 메일을 요청하면 이전 ${link?'링크는':'번호는'} 사용할 수 없어요.${link?'<br>• 인증 후 원래 버스타이머 화면으로 돌아가주세요.':''}</td></tr></table>
${fallback}</td></tr><tr><td style="padding:22px 8px;font-size:12px;line-height:21px;color:#718096">인증을 요청하지 않으셨다면 이 메일을 무시해주세요.<br>이 메일은 버스타이머에서 자동으로 발송했어요.</td></tr></table>
</td></tr></table></body></html>`;
}

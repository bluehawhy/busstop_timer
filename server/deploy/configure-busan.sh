#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"
if [ ! -f server/.env ]; then
  echo '기존 서버 설정 server/.env를 먼저 준비해주세요.' >&2
  exit 1
fi
IFS= read -r -s -p '부산 API 인증키를 붙여넣고 Enter: ' busan_setup_key
printf '\n'
export BUSAN_SETUP_KEY="$busan_setup_key"
trap 'unset BUSAN_SETUP_KEY busan_setup_key' EXIT
python3 - <<'PY'
import os,re
from pathlib import Path
from urllib.parse import unquote
value=os.environ['BUSAN_SETUP_KEY'].strip()
try:
    decoded=unquote(value,errors='strict')
except Exception:
    raise SystemExit('인증키 인코딩을 확인해주세요.')
if not re.fullmatch(r'[A-Za-z0-9+/]{32,}={0,2}',decoded):
    raise SystemExit('공공데이터포털의 일반 인증키를 확인해주세요.')
path=Path('server/.env')
content=path.read_text()
for key,setting in [('BUS_PROVIDER','busan'),('BUSAN_SERVICE_KEY',decoded)]:
    pattern=rf'^{key}=.*$'
    line=f'{key}={setting}'
    content=re.sub(pattern,lambda _:line,content,flags=re.M) if re.search(pattern,content,re.M) else content.rstrip()+'\n'+line+'\n'
path.write_text(content)
path.chmod(0o600)
print('부산 API 설정 저장 완료. 기존 DB 비밀번호와 기기 토큰은 유지했습니다.')
PY

#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

if ! command -v flutter >/dev/null 2>&1; then
  for sdk in "$HOME/flutter" "$HOME/development/flutter" /opt/flutter; do
    if [ -x "$sdk/bin/flutter" ]; then
      export PATH="$sdk/bin:$PATH"
      break
    fi
  done
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK를 찾지 못했습니다. Flutter 설치 경로를 PATH에 추가한 뒤 다시 실행하세요."
  exit 1
fi
command -v python3 >/dev/null
docker compose version

python3 - <<'PY'
from pathlib import Path
import re
import secrets

path = Path('server/.env')
text = path.read_text() if path.exists() else Path('server/.env.example').read_text()
for key in ('POSTGRES_ADMIN_PASSWORD', 'BUS_DB_PASSWORD', 'API_BEARER_TOKEN'):
    pattern = rf'^{key}=(.*)$'
    match = re.search(pattern, text, re.M)
    value = match.group(1).strip() if match else ''
    if not value or value.startswith('REPLACE_'):
        line = f'{key}={secrets.token_hex(32)}'
        text = re.sub(pattern, lambda _: line, text, flags=re.M) if match else text + '\n' + line + '\n'

pattern = r'^ALLOWED_ORIGINS=(.*)$'
match = re.search(pattern, text, re.M)
origins = [v.strip() for v in match.group(1).split(',') if v.strip()] if match else []
if 'https://bustimer.bluewaikiki.top' not in origins:
    origins.append('https://bustimer.bluewaikiki.top')
line = 'ALLOWED_ORIGINS=' + ','.join(origins)
text = re.sub(pattern, lambda _: line, text, flags=re.M) if match else text + '\n' + line + '\n'
path.write_text(text)
path.chmod(0o600)
print('환경 설정 준비 완료. 기존 비밀번호와 토큰은 유지했습니다.')
PY

flutter pub get
flutter build web --release --base-href / \
  --dart-define=BUS_API_URL=https://bustimer.bluewaikiki.top

docker network inspect bus-proxy >/dev/null 2>&1 || docker network create bus-proxy
cd server
compose=(docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml)
"${compose[@]}" config --quiet
"${compose[@]}" up -d --build --wait --wait-timeout 180
"${compose[@]}" ps
"${compose[@]}" exec -T bustimer node -e \
  "fetch('http://127.0.0.1:18082/health').then(async r=>{console.log(await r.text());process.exit(r.ok?0:1)}).catch(()=>process.exit(1))"
echo "버스 API·PostgreSQL 실행 완료. 공통 Caddy에 bustimer 도메인 설정을 적용하세요."

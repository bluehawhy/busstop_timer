# Ubuntu 버스 서버 + 전용 PostgreSQL

> 웹 배포는 [Actions·GHCR 전환 안내](../WEB_DEPLOYMENT.md)를 우선합니다. 아래의 호스트 Flutter 빌드와 build/web 배치는 이전 방식이며 새 Compose에서는 사용하지 않습니다. web 서비스가 웹을 제공하고 bustimer는 API를 제공합니다.

운영 주소: **https://bustimer.bluewaikiki.top/**. 버스 프로젝트의 Node.js 24 API와 PostgreSQL 16을 함께 실행한다. 다른 프로젝트의 PostgreSQL 컨테이너·볼륨은 사용하지 않는다.

- `bustimer`: API·Flutter Web 제공. 공통 Caddy에는 `bus-proxy`의 `bus-api:18082`로 연결한다.
- `postgres`: 버스 전용 DB. 호스트 포트와 프록시 네트워크에 연결하지 않는다.
- `postgres_data`: 이 Compose 프로젝트만 사용하는 영속 볼륨. API 이미지 교체 시 유지한다.
- DB 관리자 `bustimer_admin`과 앱 계정 `bustimer`를 분리한다. API에는 관리자 비밀번호를 전달하지 않는다.
- DB 네트워크는 `internal: true`다. API는 별도 기본 네트워크를 통해 교통 제공자에게 요청할 수 있다.

## 최초 배포

이 문서의 기본 홈서버 경로에서는 저장소 루트에서 `bash server/deploy/deploy.sh`로 환경 설정 준비·루트 경로 웹 빌드·컨테이너 실행을 한 번에 진행할 수 있다. 스크립트는 프로젝트명 `busstop_timer`를 사용하고 기존 비밀번호·토큰을 유지하며 버스 도메인을 허용 Origin에 추가한다. Flutter SDK가 PATH 또는 `~/flutter`, `~/development/flutter`, `/opt/flutter`에 필요하다. 공통 Caddy 설정은 별도로 적용한다.

신규 배포 프로젝트명은 `busstop_timer`다. 최초 실행 시 버스 전용 PostgreSQL 볼륨과 DB를 만들고 필요한 테이블을 자동 생성한다.

저장소 루트에서 웹을 빌드한다. Flutter SDK가 없는 호스트에서는 다른 빌드 환경에서 동일 명령으로 생성한 `build/web`을 배치한다. 저장소의 `web/` 소스 디렉터리로 대체하면 안 된다.

```bash
flutter pub get
flutter build web --release --base-href / --dart-define=BUS_API_URL=https://bustimer.bluewaikiki.top
cd server
cp -n .env.example .env
```

`.env`의 `POSTGRES_ADMIN_PASSWORD`, `BUS_DB_PASSWORD`, `API_BEARER_TOKEN`을 각각 다른 임의 값으로 설정한다. 각 값은 `openssl rand -hex 32`로 생성할 수 있다. DB 비밀번호는 URL에 조합하므로 16진수 문자열을 사용한다. 실제 값은 커밋하지 않는다. `chmod 600 .env`로 권한을 제한한다.

이전 예제로 `.env`를 이미 만들었다면 `ALLOWED_ORIGINS=https://bustimer.bluewaikiki.top`으로 변경한다. DB 비밀번호와 API 토큰은 유지한다. 기존 `/bustimer/`용 웹 빌드도 위의 루트 경로 명령으로 다시 빌드한다.

공통 Docker Caddy 구성에서는 Compose 2.24.4 이상이 필요하다. 프록시 overlay를 항상 마지막에 지정한다.

```bash
docker network inspect bus-proxy >/dev/null 2>&1 || docker network create bus-proxy
docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml config --quiet
docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml up -d --build --wait --wait-timeout 120
```

기본 `compose.yaml`만 실행하면 API의 `127.0.0.1:18082`가 열리며, `compose.proxy.yaml`을 함께 지정하면 그 호스트 포트를 제거한다. PostgreSQL은 어느 구성에서도 호스트에 공개하지 않는다. 기본 예제의 실제 `.env` 값이나 `docker compose config` 전체 출력은 공유하지 않는다.

`deploy/init-postgres.sh`는 새 볼륨 최초 초기화 때만 DB·역할을 만든다. 기존 볼륨에서 `.env` 비밀번호만 바꾸면 DB 비밀번호는 변경되지 않는다. 비밀번호 변경 시 DB 역할의 비밀번호와 `.env`를 함께 변경한다. 초기화 도중 오류가 나면 로그를 확인하고, 데이터가 있는 볼륨을 삭제해 복구하지 않는다.

## 공통 Caddy 연결

실행 중인 공통 Caddy 내부에서 먼저 확인한다.

```bash
cd /home/mins/source/bluewaikiki_api_server
docker compose -f compose.proxy.yaml exec -T caddy wget -qO- http://bus-api:18082/health
```

`proxy/local/caddy/Caddyfile`에 아래 독립 사이트 블록을 추가한다. DNS의 `bustimer.bluewaikiki.top`이 홈서버 공인 IP를 가리키고 기존 TCP 80/443 포워딩이 유지되어야 한다. 공통 Caddy가 HTTPS 인증서 발급과 HTTP→HTTPS 리다이렉트를 처리한다.

```caddyfile
bustimer.bluewaikiki.top {
    encode zstd gzip
    reverse_proxy bus-api:18082
}
```

웹 정적 파일과 `/api/*`, `/health`를 버스 서버가 같은 루트에서 제공한다. `/bustimer` 접두사 추가나 제거를 위한 rewrite는 사용하지 않는다. 설정 파일을 백업하고 검증 뒤 reload한다.

```bash
docker compose -f compose.proxy.yaml exec -T caddy caddy validate --config /etc/caddy/Caddyfile
docker compose -f compose.proxy.yaml exec -T caddy caddy reload --config /etc/caddy/Caddyfile
curl --fail --show-error https://bustimer.bluewaikiki.top/health
```

기존 `app.bluewaikiki.top/bustimer/` 경로를 안내용으로 유지하려면 해당 app 사이트의 버스 블록만 아래 리다이렉트로 대체한다. 나머지 app·가계부·관리 도메인 설정은 그대로 둔다.

```caddyfile
redir /bustimer https://bustimer.bluewaikiki.top/ 302
handle_path /bustimer/* {
    redir https://bustimer.bluewaikiki.top{uri} 302
}
```

버스 연결이 확인되면 다음 유지보수 때 host-relay의 `HOST_RELAY_TARGETS`에서 `bus:18082`만 제외할 수 있다. 다른 relay 항목은 계속 사용한다. 프로젝트 업데이트 때도 위의 프로젝트명과 Compose 파일 목록을 유지한다.

## DB와 기기 등록

시작 시 PostgreSQL 마이그레이션을 트랜잭션으로 적용한다. 동시에 기동하는 경우에도 마이그레이션을 직렬화한다. 최초 배포는 빈 PostgreSQL DB에서 시작한다.

```bash
cd server
docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml exec bustimer node src/server.js create-device minsu phone
```

출력된 개인 토큰은 해당 사용자에게만 전달하고 앱의 설정 화면에 입력한다. 토큰 원문은 재조회할 수 없다. 관리자 토큰은 앱에 입력하지 않는다. 생성한 기기를 철회하려면 해당 사용자의 `api_devices` 행을 삭제한다.

## 교통 데이터

초기 DB에는 가짜 정류장·버스가 없다. 실제 공급자 수집기가 아래 계약으로 관리자 인증을 통해 upsert한다. 날짜/운행일과 노선 방향을 확인하고 날짜가 지난 운행을 새 운행으로 재사용하지 않는다.

`POST /api/catalog`, `Authorization: Bearer <관리자 토큰>`

```json
{
  "stops": [{"id":"A","name":"출발 정류장","latitude":35.1,"longitude":129.0}],
  "routes": [{"id":"a-outbound","name":"a","direction":"상행","destination":"D"}],
  "routeStops": [{"routeId":"a-outbound","sequence":0,"stopId":"A","offsetSeconds":0}],
  "trips": [{"id":"provider:20261020:a:1","routeId":"a-outbound","serviceDate":"2026-10-20","source":"provider"}],
  "stopTimes": [{"tripId":"provider:20261020:a:1","sequence":0,"stopId":"A","arrivalAt":"2026-10-19T23:03:00Z","departureAt":"2026-10-19T23:03:00Z"}],
  "transfers": [],
  "headways": []
}
```

위 payload는 필드 형식 설명이며 한 정류장만으로 이동 경로가 생성되지는 않는다. 실제 노선의 모든 정차 지점과 시각을 공급해야 한다. 실시간 업데이트는 stopTimes에 `predictedArrivalAt,predictedDepartureAt,observedAt`을 포함한다. 120초가 지나면 시간표로 표시한다.

배차 기반 데이터는 `headways`에 `id,routeId,serviceDate,firstDepartureAt,lastDepartureAt,headwaySeconds,source`를 주고 `routeStops.offsetSeconds`를 채운다. 시간표가 있는 운행에 같은 배차 추정을 중복 적재하지 않는다. 휴일·운휴·막차와 시간대별 배차는 수집기가 실제 날짜별로 나누어 적재한다.

## 운영 한계

- 앱은 실행 중 15초 간격으로 알림을 확인한다. 앱 종료 상태의 APNs/FCM/Web Push는 아직 연결되지 않았다.
- 사용자별 개인 기기 토큰 인증이며 공개 가입·토큰 복원 화면은 없다.
- 실제 지역 공급자와 Ubuntu 접속 자격증명이 제공되지 않아 라이브 데이터 연결과 실제 서버 배포는 수행되지 않았다.
- 신규 기능의 상세 내용: [상세설계](../docs/DETAILED_DESIGN.md), [DB 설계](../docs/DATABASE_DESIGN.md).

## 백업 및 복구

버스 프로젝트 디렉터리에서 실행한다. `pg_dump`는 운영 중 일관된 논리 백업을 만든다. 예시는 현재 디렉터리에 파일을 저장하므로 별도 저장 장치에도 보관한다. 실패한 dump 파일은 유효한 백업으로 취급하지 않는다.

```bash
umask 077
docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml exec -T postgres \
  pg_dump -U bustimer_admin -d bustimer -Fc > bustimer-$(date +%Y%m%d-%H%M%S).dump
```

복구는 API를 중지하고 **별도의 빈 PostgreSQL DB**에 `pg_restore --exit-on-error --no-owner --no-acl`로 수행한 뒤 검증하고 전환한다. 앱 계정이 복구된 테이블을 소유하도록 `--role=bustimer`를 지정한다. 운영 DB를 대상으로 한 `--clean`, `docker compose down -v`, 볼륨 삭제는 일반 업데이트 절차에 포함하지 않는다.

장애 시 `docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml logs --tail 100 bustimer postgres`로 확인한다. `/health`는 실제 DB 쿼리도 확인하므로 DB 연결이 끊기면 성공으로 응답하지 않는다.

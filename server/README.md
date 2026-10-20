# Ubuntu 버스 서버 + 전용 PostgreSQL

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

## 정류소·버스 도착정보 API와 이력 기반 추정

모든 `/api/bus/*` 요청은 `Authorization: Bearer <개인 기기 토큰>`을 사용한다. 사용자 ID는 토큰에서 결정한다. 관리자용 정류소 매핑 변경만 관리자 토큰이 필요하다. 앱 화면의 기존 샘플 provider를 자동 교체하는 변경은 이 API 작업에 포함하지 않는다.

### 교통정보 공급자 설정

`.env`를 수정한 뒤 API 컨테이너를 다시 생성한다. DB 마이그레이션 `0003_arrival_history.sql`은 시작 시 자동 적용되며 기존 구독을 유지한다.

**TAGO:** 공공데이터포털의 [국토교통부 버스도착정보](https://www.data.go.kr/data/15098530/openapi.do) 활용 승인을 받고 디코딩 인증키를 서버에만 넣는다. 지원 도시는 해당 API의 도시코드 목록에서 확인한다. `arrtime`은 초 단위다. 미지원 도시의 정보를 이 연동으로 보장하지 않는다.

```dotenv
BUS_PROVIDER=tago
TAGO_SERVICE_KEY=공공데이터포털_디코딩_인증키
BUS_PROVIDER_DAILY_LIMIT=9000
BUS_COLLECTION_BATCH_SIZE=5
```

`POST /api/catalog`로 실제 정류소를 등록한 뒤 다음 요청으로 공급자 정류소 ID와 도시코드를 연결한다. 서버 내부 정류소 ID, 공급자 nodeId, 도시코드를 구분한다. 노선 번호(예: 472)가 아닌 공급자의 고유 routeId를 구독에 사용한다. 상·하행은 서로 다른 정류소 ID로 구분해야 한다. 순환노선이 같은 정류소를 여러 번 통과하는 경우 이 API는 통과 회차까지 구분하지 않는다.

```http
POST /api/bus/stops/내부정류소ID/provider
Authorization: Bearer <관리자 토큰>
Content-Type: application/json

{"providerStopId":"실제_TAGO_nodeId","cityCode":"실제_도시코드"}
```

매핑 변경 시 캐시만 비운다. 과거 이력은 원래 공급자 매핑 식별자로 보존하고 새 매핑의 추정에서 제외한다.

**기존 정규화 공급자:** `BUS_PROVIDER=normalized`, `BUS_ARRIVALS_URL`, 선택적으로 `BUS_API_KEY`를 설정한다. 서버는 `?stopId=<provider_stop_id 또는 내부 ID>`로 요청하고 키가 있으면 Bearer 헤더로 전달한다. 응답 계약:

```json
{"arrivals":[{"stopId":"공급자정류소ID","routeId":"고유노선ID","routeName":"표시노선번호","etaMinutes":4.5,"updatedAt":"2026-10-20T04:00:00Z"}]}
```

`updatedAt`은 선택이다. 제공되면 90초를 넘긴 오래된 데이터와 30초 이상 미래 데이터는 거부한다. 생략되면 응답 수신 시각을 관측 시각으로 사용한다. TAGO도 수신 시각을 사용하므로 `realtime` 표시는 실시간 API 출처를 뜻하며 공급자 내부 데이터의 생성 시각을 보증하지 않는다. 공급자 응답 오류/부분 응답을 빈 결과로 처리하지 않는다.

### API 목록

| API | 용도 |
|---|---|
| `GET /api/bus/stops?q=검색어` | 등록된 정류소 검색, 이름/좌표/공급자 매핑 반환 |
| `GET /api/bus/routes?stopId=ID` | 해당 정류소 카탈로그 노선 + 현재 실시간 도착 노선 목록 |
| `GET /api/bus/subscriptions` | 내 저장 정류소·버스 목록 |
| `POST /api/bus/subscriptions` | `{ "stopId":"ID", "routeId":"노선ID", "enabled":true }` 저장/활성 변경 |
| `DELETE /api/bus/subscriptions/구독ID` | 내 구독 삭제 |
| `GET /api/bus/arrivals?stopId=ID` | 내 활성 구독 노선의 실시간 도착정보, 없으면 이력 추정 |
| `GET /api/bus/predictions?stopId=ID&routeId=ID&at=ISO시각` | 특정 시각의 이력 추정만 조회; `at` 생략 시 현재 |

정류소 검색은 현재 DB 카탈로그 대상이며 공공 API 전체 정류소 검색은 별도 수집/등록이 필요하다. 노선 목록은 현재 도착 중인 노선만으로는 전체 운행 노선을 보장할 수 없다. 전체 노선을 보이려면 `/api/catalog`의 routes/routeStops도 등록한다. 정류소/노선을 저장하기 전에 `routes`를 조회한다. 공급자 노선은 90초 이내 성공 캐시 또는 카탈로그에 존재해야 저장할 수 있다. 사용자당 구독은 최대 100개다.

`arrivals`와 `predictions`는 본인의 활성 저장 노선만 조회한다. `at`은 시간대가 있는 ISO 8601 형식이며 최대 7일 뒤까지 허용한다. URL 쿼리의 `+`는 `%2B`로 인코딩한다.

### 수집·저장 정책

- 클라이언트가 닫혀 있어도 서버가 1분마다 활성 저장 정류소를 수집한다. 같은 정류소를 여러 사용자가 저장해도 공통 캐시/이력을 사용한다. 사용자 좌표는 저장하지 않는다.
- 기본 배치당 최대 5개 정류소, 오래전에 시도한 정류소부터 순환 처리한다. 저장 정류소가 많으면 정류소별 수집 간격은 1분보다 길어진다.
- 요청 시에도 갱신하며 DB의 30초 재시도 제한으로 중복 요청을 억제한다. 새 응답을 수집 중이면 기존 캐시 또는 이력을 반환할 수 있다.
- 공급자 요청 8초 제한, 서울 날짜 기준 일일 9,000회 기본 상한. 오류 호출도 상한에 포함한다. 실제 공공 API 할당량에 맞춰 조정한다. 다른 앱에서 같은 키를 쓰는 호출량은 이 서버가 계산할 수 없다.
- `bus_arrival_observations`: 내부 정류소/노선 ID, 공급자 매핑, 관측 시각, 수신 시각, 도착 예정시각, 남은 초, 첫/다음 버스 순번을 저장한다. 수집 당시 활성 저장 노선만 저장한다. 중복 공급자 관측은 재삽입하지 않는다.
- 예측 결과를 학습 이력으로 다시 저장하지 않는다. 이력과 사용량은 90일 보관한다. 구독 삭제 시 개인 연결은 삭제하지만 공통 정류소 이력은 보관기간까지 남는다.

### 추정 방식과 응답 구분

실시간 성공 캐시는 최대 90초 동안만 사용한다. 만료되거나 조회에 실패하거나 해당 노선이 응답에 없으면 이력 추정을 시도한다. 정상 실시간 응답이 비어 있는 경우에도 역사적 추정은 현재 운행을 보장하지 않으므로 `fallbackReason=NO_LIVE_ARRIVAL`을 반드시 함께 표시한다.

최근 90일 중 **같은 요일, 서울 시간 ±30분**에 해당하는 **가장 가까운 첫 버스 관측 1개를 날짜별로 선택**한다. 오늘의 반복 조회는 제외하고, 서로 다른 날짜가 최소 3개 있어야 남은 시간의 중앙값을 반환한다. 같은 요일 3개가 쌓이려면 통상 수 주가 필요하다. 10~90% 표본 범위는 보조 정보이며 통계적 신뢰구간이 아니다.

- `basis=realtime`: 공급자가 준 도착 예정정보. `expectedAt`, 현재 기준 `etaSeconds`, `fetchedAt` 포함.
- `basis=historical_estimate`: 과거 공급자 예상 대기시간 중앙값. `confidence=low`, `sampleDays`, `rangeSeconds`, `latestSampleAt`, `holidayAdjusted=false` 포함.
- `basis=unavailable`, `reason=INSUFFICIENT_HISTORY`: 표본 부족. 도착시간을 임의로 만들지 않는다.

이력은 **실제 정류소 도착/통과 확정 기록이 아니라 공급자 도착 예보의 관측 기록**이다. 공휴일·임시 운행·교통 지연·노선 개편을 보정하지 않는다. 앱은 이력 추정값을 반드시 ‘과거 이력 기반 추정’으로 구분하고 실제 알림 확정 근거로 사용하지 않아야 한다.

### 배포와 확인

저장소 루트에서 API만 재배포할 때는 기존 웹 빌드를 유지한다.

```bash
cd server
docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml up -d --build --wait bustimer
```

이후 개인 기기 토큰으로 정류소 검색 → 노선 조회 → 구독 저장 → 도착정보 조회 순서로 확인한다. `/health`는 DB 연결만 확인하며 공급자 연결 성공을 뜻하지 않는다. 키 미설정은 `providerStatus=not_configured`, 매핑 누락·상한·공급자 장애는 각각 상태 코드로 표시하며 추정 표본이 없으면 `unavailable`이다. 운영 키가 없는 개발 환경에서는 실제 공급자 통신과 PostgreSQL 수집 결과를 확인할 수 없다.

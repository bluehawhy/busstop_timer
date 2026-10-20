# Ubuntu 앱 서버 + SQLite

운영 주소: **https://app.bluewaikiki.top/bustimer/**. Node.js 24, SQLite, Flutter Web 정적 파일을 같은 서버에서 실행한다. 이전 Worker·D1 설정은 `legacy/`에 보관하며 새 기능의 배포 대상이 아니다.

## 설치 및 배포

저장소 루트에서 Flutter SDK로 웹을 빌드한다.

```bash
flutter pub get
flutter build web --release --base-href /bustimer/ --dart-define=BUS_API_URL=https://app.bluewaikiki.top/bustimer
cd server
cp .env.example .env
# .env의 API_BEARER_TOKEN을 충분히 긴 임의 값으로 수정한다.
docker compose up -d --build
```

외부에 직접 DB나 API 포트를 열지 않는다. `127.0.0.1:18082`만 공개하고 Caddy의 기존 `app.bluewaikiki.top` 블록에 `deploy/Caddyfile.snippet`을 추가한다. `handle_path`로 접두사를 제거하지 않는다. 다른 `/ledger/` 등 서비스 블록은 유지한다.

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
docker compose logs --tail 100 bustimer
curl https://app.bluewaikiki.top/bustimer/health
```

Docker 없이 실행하려면 `server/`에서 Node 24로 `npm start`한다. 이 경우 기본 host는 127.0.0.1, DB는 `./data/bustimer.sqlite`, 웹은 `../build/web`다. 운영은 Docker의 `restart: unless-stopped`를 사용한다.

## DB와 기기 등록

시작 시 파일별 트랜잭션 마이그레이션이 자동 적용된다. 기존 구독 테이블은 삭제하지 않는다. D1에 있던 데이터를 Ubuntu로 자동 복사하지는 않는다.

```bash
cd server
docker compose exec bustimer node src/server.js create-device minsu phone
```

출력된 개인 토큰은 해당 사용자에게만 전달하고 앱의 설정 화면에 입력한다. 토큰 원문은 재조회할 수 없다. 관리자 토큰은 앱에 입력하지 않는다. 생성한 기기를 철회하려면 해당 사용자의 `api_devices` 행을 삭제한다.

## 교통 데이터

초기 DB에는 가짜 정류장·버스가 없다. 실제 공급자 수집기가 아래 계약으로 관리자 인증을 통해 upsert한다. 날짜/운행일과 노선 방향을 확인하고 날짜가 지난 운행을 새 운행으로 재사용하지 않는다.

`POST /bustimer/api/catalog`, `Authorization: Bearer <관리자 토큰>`

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

## 백업

볼륨 `server/data`를 유지한다. 실행 중 백업은 sqlite3 `.backup`을 사용하거나 서비스를 중단한 뒤 DB를 복사한다. 서버 재시작·이미지 교체 시 `docker compose down -v`나 data 디렉터리 삭제를 하지 않는다. 장애 시 `docker compose logs`와 `/bustimer/health`로 확인한다.

## 공통 Docker Caddy 연결 (선택 적용)

공통 게이트웨이로 전환할 때만 `server/compose.proxy.yaml`을 기존 Compose 파일 목록의 마지막에 추가합니다. `bustimer`의 호스트 포트를 제거하고 외부 `bus-proxy` 네트워크에서 `bus-api:18082`로 접근합니다. Node 서버의 내부 포트와 `/bustimer` 접두사는 그대로 유지합니다. Caddy는 `handle /bustimer/*`을 사용하며 `handle_path`로 접두사를 제거하지 않습니다.

Docker Compose 2.24.4 이상이 필요합니다. 적용 전에 공통 서버에서 `bus-proxy`를 생성하고, 기존 프로젝트명과 모든 운영 Compose/override 파일을 확인합니다. 기존 bind 데이터 경로와 프로젝트명을 유지하여 DB를 보존합니다. 프록시 파일은 기본 설정에 자동 적용되지 않으며 PR 병합만으로 운영 포트가 바뀌지 않습니다.

실제 포트 제거는 호스트 Caddy에서 Docker Caddy로 전환하는 유지보수 구간에 실행합니다. 먼저 기존 포트를 남긴 상태에서 내부 DNS와 `/bustimer/health` 응답을 확인합니다. 적용 후 CLI 업데이트도 모든 기존 Compose 파일과 마지막 프록시 파일을 함께 사용합니다. 되돌릴 때는 프록시 파일만 제외하고 동일 프로젝트/서비스를 재생성합니다.

전체 절차: [공통 프록시 구성](https://github.com/bluehawhy/bluewaikiki_api_server/blob/main/proxy/README.md).

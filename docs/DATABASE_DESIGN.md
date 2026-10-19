# DB 구조 상세설계

## 운영 환경과 호환성

Ubuntu에서 Node.js 24 API와 SQLite를 실행한다. DB 파일은 `server/data/bustimer.sqlite`, Docker에서는 `/data/bustimer.sqlite`다. WAL·외래키·5초 busy timeout을 적용한다. 단일 홈서버 프로세스 운영을 기준으로 하며 다중 인스턴스 DB 파일 공유는 지원하지 않는다.

기존 `0001_initial.sql`은 유지한다. `0002_journeys.sql`은 추가 테이블만 생성하고 `schema_migrations`에 성공한 파일을 기록한다. 파일별 트랜잭션으로 적용하며 실패 시 롤백한다. 기존 D1 데이터를 자동 이전하지는 않는다. 운영 D1 데이터가 있다면 별도 export/import가 필요하다.

## 테이블

| 테이블 | 키·관계 | 역할 |
|---|---|---|
| users | id PK | 사용자 식별 |
| api_devices | token_hash PK, user_id FK | 기기 토큰 SHA-256 해시와 소유자 |
| stops | id PK | 정류장 이름·좌표, 기존 테이블 재사용 |
| routes | id PK | 방향·분기별 노선 이름·행선지 |
| route_stops | route_id + sequence PK | 정차 순서, 정류장 FK, 기점 기준 누적 주행초 |
| trips | id PK, route_id FK | 실제 운행 식별, 운행일·데이터 출처 |
| stop_times | trip_id + sequence PK | 정류장별 시간표 및 실시간 예측·관측 시각 |
| headway_windows | id PK, route_id FK | 특정 운행일의 첫/마지막 기점 출발과 배차간격 |
| transfers | from_stop_id + to_stop_id PK | 방향성 환승 도보 연결 |
| saved_journeys | id PK, user_id FK | 출발/목적지, 이름·요일·한국 시각 |
| journey_options | id PK, user_id FK | 검색 결과와 요청 JSON, 선택 유효기간 10분 |
| journey_sessions | id PK, user_id FK | 선택된 구간 JSON, 진행 구간·상태·revision |
| journey_alerts | id PK, session_id FK | 구간/차량별 알림 outbox와 수신 확인 |
| subscriptions / alert_events / device_tokens | 기존 유지 | 이전 API 호환 전용, 새 앱은 사용하지 않음 |

JSON 스냅샷에는 선택한 버스 조합과 계산 근거를 보존한다. 외부 클라이언트가 임의 경로 JSON을 보내 이동 세션을 만들 수 없고, 서버가 보관한 본인 option ID만 선택한다.

## 시간과 식별 규칙

모든 절대 시각은 UTC ISO 8601 밀리초 문자열로 정규화한다. 운행일은 지역의 날짜이며 자정 이후 운행은 다음 날짜 절대 시각으로 기록한다. `departure_time`은 `Asia/Seoul` 기준 HH:mm, 요일은 월=1~일=7 JSON 배열이다. 서버는 저장 시간대만으로 자동 이동을 시작하지 않는다. 앱에서 다음 반복 요일을 선택해 검색한다.

`route_id`는 방향·분기별로 분리한다. `trip_id`는 한 차량의 한 운행을 안정적으로 식별하며 제공자가 차량 번호만 주면 날짜·운행회차를 포함해 정규화한다. 배차 추정 차량 키는 `headway:windowId:기점출발epoch`다.

## 제약·인덱스

정류장 좌표 범위, 상태 enum, 배차간격 60~14400초, 환승 도보 0~1800초, 외래키를 적용한다. 경로 검색용 정류장/시간 인덱스, 사용자별 저장·세션 인덱스, 알림 미확인 인덱스를 둔다. 알림은 `(session_id,leg_index,vehicle_key,kind)` 유일 제약으로 서버 재시작 후에도 중복 생성을 방지한다.

## 데이터 수명·백업

검색 결과는 10분 후 삭제한다. 이동 세션·저장 경로·알림은 현재 자동 삭제하지 않는다. 운영 전 보존 기간을 정하고 정리 작업을 추가해야 한다. 기기 토큰 철회는 해당 `api_devices` 행 삭제로 처리한다. 위치 좌표·이동 경로 GPS 이력은 수집하지 않는다.

라이브 백업은 SQLite `.backup` 명령을 사용한다. 파일만 복사하려면 서버를 중단한 뒤 DB 파일과 WAL 상태를 정리하고 복사한다. 롤백은 새 앱/API를 이전 버전으로 되돌리되 추가 테이블은 유지한다. DB 파일을 삭제하거나 초기 마이그레이션을 다시 만드는 방식으로 롤백하지 않는다.

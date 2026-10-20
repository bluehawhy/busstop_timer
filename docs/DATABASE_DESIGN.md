# DB 구조 상세설계

## 운영 환경과 호환성

Ubuntu에서 Node.js 24 API와 버스 프로젝트 전용 PostgreSQL 16 컨테이너를 실행한다. 다른 프로젝트 DB 컨테이너와 볼륨을 공유하지 않는다. `postgres_data` named volume에 데이터를 보관하며 PostgreSQL은 호스트 포트를 공개하지 않는다. API만 내부 DB 네트워크와 공통 프록시 네트워크를 연결한다.

관리자 `bustimer_admin`과 앱 계정 `bustimer`를 분리한다. 앱 계정은 전용 `bustimer` DB를 소유하며 superuser·DB 생성·역할 생성 권한이 없다. DB 접속 풀은 API 프로세스당 최대 5개다. 모든 트랜잭션은 하나의 풀 연결에서 수행하고 세션 평가 시 행 잠금, 상태 변경 시 revision 조건과 갱신 행 수를 확인한다.

`server/migrations/postgres/`의 SQL과 별도 `schema_migrations`를 사용한다. 마이그레이션은 advisory transaction lock과 단일 트랜잭션으로 적용한다. 원래 SQLite 마이그레이션은 기존 스키마 참고용으로 보관하며 PostgreSQL에서 실행하지 않는다. SQLite 데이터는 읽기 전용 가져오기 도구로 비어 있는 대상 DB에 명시적으로 복사한다. D1 원격 DB의 자동 이전은 지원하지 않는다.

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

라이브 백업은 `pg_dump -Fc`를 사용한다. API를 중지한 유지보수 시간에 별도의 빈 DB로 `pg_restore`한 뒤 확인한다. API 이미지 교체와 DB 볼륨은 별도로 관리한다. 기존 SQLite 원본은 전환 후에도 보관하고 자동 삭제하지 않는다. PostgreSQL에 새로 생성된 데이터는 SQLite로 자동 역이관되지 않는다. 상세 명령과 복구 절차는 [운영 안내](../server/README.md)를 따른다.

# 버스타이머 대중교통 중심 지도: 디자인 · 구현 · 운영

> 2026-11-11. 이전 지도 전체 커스터마이징 설계와 **웹·모바일 공통 모바일 UI** 설계를 통합한 구현 기준.
> 이 문서의 구현 상태는 브랜치 `feat/transit-mobile-map-20261111` 기준이다.

## 1. 디자인 참고

사용자가 선택한 Acfas 대중교통 안내도 디자인을 비주얼 레퍼런스로 사용한다.

![대중교통 노선도 디자인 참고 이미지](https://images.openai.com/static-rsc-4/k-W7DEV0kjsghIjXoYi6hhmCmdAWN__RXnWtFup3PlbGUsnJ6CJLY4riZZHauhIwibxhi6HtjwTKuCfLqfejj7TnkaMAWHR8dO8JIsFEWRAXrNQVSHvs75NkEMEzwjJf_UuEFTP8oZihoIczaGuH2Vyb7qUeD7iCB400OCB_kP8?purpose=inline)

[참고 이미지 원본](https://images.openai.com/static-rsc-4/k-W7DEV0kjsghIjXoYi6hhmCmdAWN__RXnWtFup3PlbGUsnJ6CJLY4riZZHauhIwibxhi6HtjwTKuCfLqfejj7TnkaMAWHR8dO8JIsFEWRAXrNQVSHvs75NkEMEzwjJf_UuEFTP8oZihoIczaGuH2Vyb7qUeD7iCB400OCB_kP8?purpose=inline)

이 이미지는 외부 리소스 링크로만 참조하며 저장소에 복제하지 않는다.

### 시각 규칙
- **대중교통 중심**: 실제 도로 형상 위에서 노선·정류장을 강조하고 상업시설 POI는 생략한다.
- **배경**: 교통 안내도용 연회색 `#F3F5F3`, 흰색 주요 도로 `#FFFFFF`, 회색 건물 `#DDE4E2`, 연녹색 공원 `#E1EEE4`, 청록빛 수계 `#D0E9ED`. 주요 도로와 골목을 별도 레이어로 나누고 건물·도로명은 확대 단계에 맞춰 낮은 대비로 보여준다.
- **노선 팔레트**: 주황 `#F36A2B`, 분홍 `#EA1658`, 연두 `#7BC65B`, 노랑 `#F5AE16`, 청록 `#009CA5`. 노선 ID의 안정적 해시를 사용해 색을 선택한다.
- **정류장**: 기본은 연백색 내부 `#F9FDFB` + 청록 테두리 `#438985`의 작고 비어 보이는 원형 마커(줌에 따라 반경 3.2~5.1px). 선택하면 주황색 `#F36A2B` 반경 8.5px + 흰 테두리. 정류장 번호는 충분히 확대했을 때만 최대 18개, 이름은 더 가까운 확대에서 최대 25개만 표시하여 혼잡도를 낮춘다.
- **실제 노선 형상만 표시**: 정류장 좌표를 직선으로 이어서 실제 도로처럼 보이게 하지 않는다. 공식 형상이 있을 때는 10px 흰색 테두리 위에 6px 컬러 노선을 그려 지도 배경과 구분한다.
- **정류장 선택**: 지도 위의 모바일 카드에서 이름·정류장번호·노선 목록과 등록 동작을 제공한다. 홈 지도 헤더 뒤에는 짧은 반투명 그라데이션을 두어 정류장 마커가 제목과 겹쳐 보여도 가독성을 확보한다.

## 2. 웹에서도 모바일 화면

- 모든 웹, Android, iOS 화면은 **430 논리 픽셀 최대 폭**의 동일한 세로 UI를 사용한다.
- 좁은 브라우저에서는 너비 100%, 넓은 브라우저에서는 화면 가운데 배치하며 바깥 배경은 `#E9EEF3`이다.
- 홈에는 지도 배경, 상단 정류장 검색, 지도 안내, 하단 드래그 가능한 도착정보 바텀시트가 배치된다.
- 전체 화면에 걸친 데스크톱 사이드레일이나 2열 경로 화면은 사용하지 않는다. Navigator와 모달 역시 모바일 폭으로 제한한다.
- 지도 영역은 손가락 드래그·핀치 확대·축소, 마우스 드래그·휠 확대를 지원한다.
- `web/index.html`에서 모바일 viewport와 테마색을 지정한다.

## 3. 시스템 구성

```text
Flutter 웹/Android/iOS
 ├─ MapLibre GL 지도 + 모바일 UI
 │   ├─ Flutter asset: assets/map/bus_transit_style.json
 │   └─ OpenFreeMap 벡터 타일 (OpenStreetMap 원천)
 └─ JourneyService (기기/게스트 Bearer 토큰)
     ├─ GET /api/bus/map/stops             # viewport 내 정류장
     ├─ GET /api/bus/routes?stopId=...      # 선택 정류장 노선
     ├─ GET /api/bus/map/route?routeId=... # 검증된 노선 형상
     └─ POST /api/bus/subscriptions         # 버스 등록

Node.js 24 + PostgreSQL 16
 ├─ stops + bus_catalog_entries / bus_catalog_regions
 ├─ routes + route_stops                    # 실제 도로 형상과 다름
 ├─ bus_route_shapes                       # 검증된 LineString만
 └─ 버스 제공자별 정류장 수집 및 도착정보 연동
```

### 현재 지도 제공 범위

| 구분 | 구현 | 주의사항 |
|---|---|---|
| 벡터 지도 | 구현 | 초기에는 OpenFreeMap 공개 타일 이용; 이후 자체 PMTiles 전환 가능 |
| 도로·건물·공원·하천 스타일 | 구현 | MapLibre Style JSON 편집으로 색상·표시 조건 수정 |
| 실제 정류장 마커 | 구현 | DB 좌표가 등록된 정류장만 표시 |
| 지도 선택 정류장 노선 목록 | 구현 | 제공자 또는 카탈로그에 노선 정보가 있어야 함 |
| 경로 선 | 데이터 존재 시 구현 | 검증된 `bus_route_shapes`만 표시 |
| 지도에서 노선 등록 | 구현 | ETA는 등록 시 생성하지 않으며 별도 도착정보 조회 사용 |
| 실제 움직이는 버스 아이콘 | 미구현 | 제공자별 차량 GPS·갱신 주기·사용 허가 확인 후 도입 |
| 자체 PMTiles 파일 제작/호스팅 | 미구현 | OSM→Planetiler→PMTiles→정적 파일 서버/R2 계획 |
| 사용자 GPS 표시 | 미구현 | 사용자 권한 없이 실제 위치를 추정·표시하지 않음 |

현재 초기 중심 위치는 **부산광역시**이며 사용자가 지도를 자유롭게 이동할 수 있다. API 카탈로그에 해당 영역의 정류장이 없으면 정류장 마커는 나타나지 않는다.

## 4. 지도 API 계약

### 정류장 범위 조회

`GET /api/bus/map/stops?south=35.17&north=35.19&west=129.06&east=129.09`

WGS84 위도·경도를 받아 사각 범위 내 정류장을 조회한다.
- 경도·위도 경계 검증, 뒤집힌 범위 거부.
- 한 번에 남북 또는 동서 0.4도 초과 시 `zoomRequired:true`와 빈 목록을 반환.
- 화면 중심에 가까운 정류장부터 **최대 250개** 제공. 추가 결과가 있으면 `truncated:true` 반환.
- 응답 필드: `stops:[{id,name,latitude,longitude,arsNo}]`, `truncated`, `zoomRequired`.
- 클라이언트는 카메라 이동이 끝난 뒤 요청하며 중복 요청은 병합한다.

### 검증된 노선 형상 조회

`GET /api/bus/map/route?routeId=<route_id>`

- 등록된 경우: `{routeId,verified:true,routeName,source,geometry:{type:"LineString",coordinates:[[lng,lat],...]}}`.
- 없는 경우: `verified:false,geometry:null`. 이때 지도에 가상의 선을 그리지 않는다.
- 경로 방향이나 노선 분기별 형상이 필요해지면 노선 식별키를 방향 단위로 세분화한다.

### 운영자 전용 노선 형상 등록

`POST /api/bus/map/route` (서버의 `API_BEARER_TOKEN` 필요):

```json
{
  "routeId": "provider_route_key",
  "routeName": "100",
  "source": "공식 제공자 명칭/검증일",
  "geometry": {
    "type": "LineString",
    "coordinates": [[129.07,35.17],[129.08,35.18]]
  }
}
```

위 좌표는 **API 형식 설명용 가상 예시**이며 실제 경로 데이터로 사용하지 않는다.
저장 시 좌표 유효범위·개수(2~10,000개)를 검사하고 PostgreSQL `bus_route_shapes`에 저장한다. 정류장·실시간 도착 기록은 변경하지 않는다.

## 5. 화면 확대에 따른 표현

| 확대 수준 (초기 기준) | 표현 |
|---|---|
| 낮음 (광역) | 지형·도로 중심, 정류장은 숨기고 확대 안내 |
| 중간 (동네) | 청록색 테두리의 작은 원형 정류장 마커, 전체 API 표시 한도 250개 |
| 높음 (정류장 주변) | 확대 범위에 따라 마커 반경 증가, 정류장번호·이름은 소수만 표시 |
| 노선 선택 | 검증된 형상만 6px 컬러 라인으로 강조, 없으면 명시적 안내 |

현재 구현은 정류장 이름/번호 노출을 카메라 가시 범위의 위도 높이로 판단한다. 향후 지도 zoom값 또는 군집화 알고리즘으로 고도화할 수 있다.

## 6. 저장 및 갱신 정책

- **지도 기초 데이터**: OpenStreetMap 라이선스(ODbL) 조건 및 지도 출처 표기 필요.
- **지도 타일**: OpenFreeMap 공개 서비스는 초기 운영·검수용. 캐싱/서비스 수준을 고정하려면 자체 배포로 변경.
- **정류장 데이터**: 기존 부산/TAGO 데이터 수집 파이프라인을 그대로 사용. 현재 카탈로그 갱신은 지역별 스케줄에 따른다.
- **노선 형상**: 운영자가 공식 출처로 검증해 등록한 경우에만 출력. ETA 또는 운행 상태와 혼동하지 않는다.
- **실시간 도착**: 기존 `/api/bus/arrivals`를 사용하며 지도 도형에 ETA나 GPS를 추정해 붙이지 않는다.
- **PMTiles 전환 목표**: OSM 추출 → Planetiler 타일 생성 → PMTiles → R2/정적 서버 → `style.json`의 소스 변경. 브라우저 HTTP Range·CORS·오프라인 정책 별도 검토.
- **폰트·배포**: 초기 글리프는 공개 MapLibre 데모 엔드포인트에 의존하므로 자체 운영 시 자체 glyph CDN 전환 필요.

## 7. 적용 파일과 배포

- `lib/main.dart`: Navigator 단위 최대 430px 레이아웃.
- `lib/bus_home_page.dart`: 항상 모바일 하단 메뉴, 지도 안내 문구.
- `lib/widgets/stop_map_preview.dart`: MapLibre, 정류장 API 및 지도 UI.
- `assets/map/bus_transit_style.json`: 지도 스타일.
- `pubspec.yaml`: `maplibre_gl ^0.27.1`, 스타일 에셋.
- `server/src/bus-api.js`: 범위 조회/검증 노선 조회·등록.
- `server/migrations/postgres/0008_bus_map_shapes.sql`: 노선 형상 테이블.
- `web/index.html`: 모바일 viewport.

배포 전에 `flutter pub get`으로 의존성 잠금을 갱신하고 Flutter Web을 빌드해야 한다. 서버는 시작 시 미적용 SQL 마이그레이션을 자동 적용한다. Android 네이티브 빌드에는 MapLibre 플러그인이 요구하는 JDK 21 환경도 확인한다.

**주의**: 이 브랜치에서는 테스트 코드 추가 및 테스트 실행을 진행하지 않았다. 디자인 참고 이미지와 실제 국내 정류장 데이터의 정확도는 별도 수동 검수가 필요하다.

## 8. 운영 API 도메인 · 기존 정류장 복원 (2026-11-11)

대시보드에 등록된 프로젝트 slug는 **`bustimer`**다. 플랫폼 라우터는 slug 기준으로 외부 API 주소를 `https://api.bluewaikiki.top/bustimer`에 공개하며 경로를 삭제하지 않고 Function에 전달한다. 서버의 `BASE_PATH`도 **`/bustimer`**여야 한다.

| 항목 | 적용해야 하는 운영값 |
|---|---|
| 대시보드 프로젝트 slug | `bustimer` (변경하지 않음) |
| 웹 주소 | `https://app.bluewaikiki.top/bustimer/` |
| 공개 API 기본 주소 | `https://api.bluewaikiki.top/bustimer` |
| 서버 런타임 `BASE_PATH` | `/bustimer` |
| 서버 런타임 `ALLOWED_ORIGINS` | `https://app.bluewaikiki.top` |
| 서버 런타임 `AUTH_EMAIL_LINK_URL` | `https://api.bluewaikiki.top/bustimer/api/auth/verify` |

**이전 잘못된 경로:** `https://api.bluewaikiki.top/busstop_timer`는 프로젝트 slug와 불일치해 플랫폼 라우터에서 Function을 찾을 수 없다. 별도 독립 호스트인 `https://bustimer.bluewaikiki.top`는 이전 배포 구성이므로 운영 앱의 기본 경로로 사용하지 않는다.

- `JourneyService`와 경로 검색 화면은 같은 `BUS_API_URL` 기본값을 사용한다. 앱 빌드에 `BUS_API_URL`이 제공되면 이를 우선 사용하며, 제공되지 않으면 `https://api.bluewaikiki.top/bustimer`를 사용한다.
- 대시보드 웹 빌드가 주입하는 `PUBLIC_API_URL`은 현재 Flutter `JourneyService`에서 직접 읽지 않는다. 프로젝트 slug 기반의 공개 URL이 정확하더라도 `BUS_API_URL`이 잘못 지정되면 앱이 엉뚱한 서버로 연결될 수 있다.
- 기존 브라우저 출처가 유지되면 `SharedPreferences`의 이전 경로별 게스트 토큰을 새 API 저장 키로 이전할 수 있다. `auth/status`에서 401로 거절되어도 오래된 키를 자동 삭제하지 않고, 현재 API에서 새 게스트 토큰을 발급한다. 명시적 로그아웃 시에는 이전 키도 삭제한다.
- 브라우저 출처 자체가 바뀌면 브라우저 보안 정책 때문에 옛 출처의 저장소를 자동 조회할 수 없다. 이메일로 연결한 계정은 다시 인증해 복구할 수 있지만 연결하지 않은 게스트 계정은 별도 복구 방안이 필요하다.
- 홈 화면은 서버의 `bus/subscriptions`를 자동 조회해 기존 등록 정류장과 버스를 복원한다. 일시적인 도착정보 오류로 등록 내역을 지우지 않는다.
- **서버 런타임 변수**는 Git에 저장되지 않으므로 코드 PR만 머지해도 `BASE_PATH`가 바뀌지 않는다. 대시보드의 환경변수에 `BASE_PATH=/bustimer`와 정확한 인증 링크를 저장하고 런타임에 적용해야 한다. 이 설정을 바꾸기 전까지 기존 Function은 새 경로에서 정상 동작하지 않을 수 있다.
- **배포 순서:** 수정된 Flutter 웹을 빌드할 준비 → 서버 런타임 경로 수정·적용 → 공개 `/bustimer/api/` 응답 확인 → 수정된 웹 빌드 배포 → 게스트 인증 및 기존 구독 복원 확인. 서버 재시작 순간의 짧은 연결 중단 가능성을 고려한다. DB 삭제나 계정 초기화는 필요하지 않다.

별도 수동 Compose 배포용 `server/deploy/deploy.sh`, `server/.env.example` 및 `server/README.md`는 현재 플랫폼 운영과 구별해야 한다. 플랫폼 런타임 변수 예시는 `server/deploy/platform-runtime.env.example`을 참고한다.

## 9. 확정 디자인 조합 구현 (2026-11-12)

사용자가 선택한 **1번 지도 + 4번 정류장 아이콘·노선·하단 배너**를 적용한다. 구현은 `feat/bus-map-selected-design-20261112` 브랜치를 기준으로 한다.

| 화면 요소 | 구현 기준 |
|---|---|
| 지도 배경 | 1번 시안처럼 밝은 회청색 건물(`#E7EDF2`), 흰색 골목, 노란 계열 주요 도로, 선명한 연녹색 공원과 하늘색 물 레이어 |
| 정류장 아이콘 | 4번 시안처럼 일반 정류장은 청록색 원형 배경에 흰색 버스 픽토그램, 선택 정류장은 주황색 버스 픽토그램 |
| 노선 | 4번 시안처럼 진한 파란색 `#246BFA`(6px)과 흰색 외곽선(10px). **공식 검증된 GeoJSON 형상이 있을 때만 그린다** |
| 위치 선택 | 상단 칩에 `부산광역시 연제구`처럼 시·구를 표시하고 구·군 선택 시 지도 중심을 해당 지역으로 이동. 부산 15개 구 + 기장군 지원 |
| 하단 정보 | 4번 시안의 청록색 그라데이션 배너, 버스 아이콘, 흰 카드 1~2개에 등록된 노선의 실제 도착정보 표시 |
| 정보 부재 | 실제 도착정보/등록 내역이 없으면 안내 문구만 노출. 시안 속 예시 숫자나 도착 시간을 생성하지 않는다 |
| 모바일 웹 | PC·모바일 동일한 최대 430px 세로 UI 유지. 하단 바텀시트는 이동/확대 가능 |

### 동작 및 데이터 주의사항

- 구·군별 지도 시작 좌표는 위치 이동을 위한 **근사 앵커**이며 행정구역 경계 데이터나 GPS 역지오코딩 결과가 아니다. 상단 칩은 사용자가 선택한 탐색 지역을 나타낸다. 지도 드래그만으로 자동 주소를 변경하는 기능은 포함되지 않는다.
- 마커는 `dart:ui`의 Canvas로 생성한 PNG를 MapLibre의 `addImage` + `SymbolOptions`에 등록한다. 외부 이미지를 다운로드하거나 폰트 그림문자에 의존하지 않는다.
- 기존 정류장·노선·도착 API, 사용자 인증과 서버 DB에는 변경이 없다. 실제 도착정보는 기존 저장된 구독을 통해 조회하며, 구독하지 않은 정류장에 임의의 시간을 표시하지 않는다.
- 노선·도착시간·정류장 위치는 API가 제공하는 실제 값만 사용한다. 최초 디자인 목업에 표현된 도착시간과 노선 형상은 참고 이미지일 뿐 실제 서비스 데이터가 아니다.
- 파일: `assets/map/bus_transit_style.json`, `lib/widgets/stop_map_preview.dart`, `lib/widgets/bus_stop_marker.dart`, `lib/widgets/busan_map_regions.dart`, `lib/bus_home_page.dart`.
- 이번 변경에서 테스트 코드 추가 및 테스트 실행은 수행하지 않았다. PR 리뷰 후 웹을 빌드하면 앱 레이아웃과 지도 벡터 스타일이 함께 반영된다.

## 10. 지도 터치로 하단 정류장 패널 표시 전환 (2026-11-12)

- 홈 지도 초기 진입 시 하단 정류장 정보 패널은 화면 높이의 43%로 표시한다.
- 지도 빈 공간을 터치하면 패널이 부드럽게 화면 아래로 내려가 완전히 숨겨진다(높이 0%). 선택된 정류장과 저장된 버스 데이터는 삭제하지 않는다.
- 지도 정류장 마커 또는 정류장 라벨을 터치하면 해당 정류장을 선택하면서 하단 패널을 다시 43% 높이로 올린다.
- MapLibre의 마커 터치는 배경 지도 터치로 처리하지 않아 열기·닫기 동작이 충돌하지 않는다.
- 기존 드래그로 패널 높이를 조절하는 기능과 최대 82% 높이는 유지한다.
- 지도·패널 UI 변경에 한정하며 서버 API, DB, 구독 정보에는 영향이 없다.
- 테스트 코드 추가 및 자동 테스트 실행은 진행하지 않았다.

## 10. 실제 지도 가독성 보정 (2026-11-13)

### 작업 배경
승인 시안은 렌더링 예시로, 실제 부산의 도로 구조나 건물/정류장 좌표와 일치하지 않는다. 실서비스는 **OSM/OpenFreeMap의 실제 지형과 정류장 카탈로그 좌표를 보존**하면서 지도의 스타일만 시안에 가깝게 보정한다. 그려진 도로의 위치나 교차로 형상은 인위적으로 바꾸지 않는다.

### 지도 스타일 변경
- 노란색 도로 외곽선 과도 강조 방지: 주요 도로를 `motorway/trunk`, `primary/secondary`, `tertiary`, `minor/residential/service`로 분리해 채도와 너비를 다르게 적용한다.
- 주요 도로는 둥근 선 끝/연결부(`line-cap/line-join: round`)와 약한 베이지색을 사용한다. 기존 실제 도로 선형에는 손대지 않는다.
- 건물 윤곽선과 고확대 단계의 채도를 보완해 도심 블록 구분을 개선한다.
- 공원과 수역은 녹색/하늘색으로 더 분명하게 표시한다.
- `place`의 동네·지역명과 `poi`의 공원·학교·관공서·역 이름을 OSM 타일에 존재할 때만 표기한다. 이름이나 랜드마크를 하드코딩하지 않는다.

### 정류장 아이콘 밀도
- 지도 API는 기존처럼 뷰포트 내 실제 정류장을 반환한다. 표시 측에서는 **화면 좌표에 비례한 그리드**를 적용하여 인접한 아이콘을 제한한다.
- 넓은 범위에서는 셀 간격을 약 73~88 논리 px, 중간 확대는 55px, 근접 확대는 37px로 변경한다.
- 모든 정류장은 원래 위도·경도를 유지하며 밀도를 줄이기 위해 아이콘을 임의로 이동시키지 않는다.
- 선택된 정류장은 같은 셀 내 다른 정류장보다 우선 렌더링한다.
- 일반 버스 픽토그램은 확대 수준에 따라 0.31~0.40배로 표시하며 선택 버스는 0.53배로 강조한다.
- 정류장 이름·번호는 더 가까운 확대에서만 제한된 수로 제공한다.
- 겹쳐서 숨겨진 정류장은 지도를 확대하거나 기존 정류장 검색을 이용해 찾는다. 이는 데이터 삭제나 API 필터 변경이 아니다.

### 유지사항 및 제한
- 선택한 구/군 선택 칩, 선택한 노선의 파란색 **공식 검증 경로만 표시하는 정책**, 하단 청록색 도착 배너와 인증/정류장 등록은 그대로 유지한다.
- 실제 OSM 타일에 지역명 또는 POI가 없는 곳은 라벨이 표시되지 않는다.
- 목업의 임의 지형·가상 건물·가상 도로·임의 버스 도착시간을 실 지도에 덧그리지 않는다.
- 이번 수정은 Flutter 지도 스타일/표시 로직과 문서만 포함하며 API/DB 수정 및 테스트 코드 추가/테스트 실행은 하지 않는다.

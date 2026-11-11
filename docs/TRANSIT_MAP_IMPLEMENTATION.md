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
- **배경**: 종이색 `#F8FAFC`, 도로 `#FFFFFF`, 건물 `#E5E9EF`, 공원 `#E4F3E7`, 수계 `#CDE9F9`, 도로 테두리 `#D7DDE5`.
- **노선 팔레트**: 주황 `#F36A2B`, 분홍 `#EA1658`, 연두 `#7BC65B`, 노랑 `#F5AE16`, 청록 `#009CA5`. 노선 ID의 안정적 해시를 사용해 색을 선택한다.
- **정류장**: 파란색 원형 마커, 선택 중 분홍색 강조, 흰색 테두리. 확대 시 정류장번호와 이름을 보여준다.
- **실제 노선 형상만 표시**: 정류장 좌표를 직선으로 이어서 실제 도로처럼 보이게 하지 않는다.
- **정류장 선택**: 지도 위의 모바일 카드에서 이름·정류장번호·노선 목록과 등록 동작을 제공한다.

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
| 중간 (동네) | 실제 정류장 원형 마커, 겹침 우려 시 최대 250개 중심 우선 |
| 높음 (정류장 주변) | 마커 + 정류장번호, 가까이 확대하면 정류장명까지 표시 |
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

# Bus Timer UI Concept

초기 디자인 시안입니다. 실제 화면 구현 전 정보 구조와 색상, 사용 흐름을 검토하기 위한 컨셉 이미지입니다.

## 화면 목록

| 화면 | 파일 | 목적 |
|---|---|---|
| 전체 컨셉 보드 | [design-overview.png](design-overview.png) | 모바일 핵심 흐름과 웹앱 방향 한눈에 보기 |
| 홈 | [home.png](home.png) | 현재 위치, 30m 정류장 반경, 가까운 버스 |
| 정류장 찾기 | [stop-search.png](stop-search.png) | 주변 정류장 검색 및 등록 |
| 내 버스 | [my-buses.png](my-buses.png) | 등록 노선과 도착정보 관리 |
| 알림 설정 | [alert-schedule.png](alert-schedule.png) | 5분 전 기준, 요일과 시간대 설정 |
| 도착 알림 | [arrival-alert.png](arrival-alert.png) | 버스 ETA와 정류장 정보 확인 |
| 설정 | [settings.png](settings.png) | 푸시·위치 권한, 개인정보 안내 |
| 웹 대시보드 | [web-dashboard.png](web-dashboard.png) | 큰 화면에서 등록 정류장과 노선 관리 |

## 디자인 방향

- 아이보리 바탕, 딥 틸 기본 동작 색상, 라임 알림 강조색
- 큰 ETA 숫자와 명확한 노선/정류장 표시
- 위치 정확도와 데이터 갱신 시각을 함께 보여 신뢰도 판단 지원
- 30m는 초기 컨셉 값이며 실제 GPS 오차와 정류장 좌표를 검증해 조정
- 화면 속 지역/노선 정보는 시각적 예시이며 실제 교통 데이터가 아님

## 유의사항

이미지는 생성형 시각 시안입니다. 작은 글자, 지도 지명, 정류장·노선 정보는 정확한 서비스 데이터가 아니며 구현 사양으로 간주하지 않습니다. 실제 UI는 플랫폼 디자인 가이드, 접근성, 위치 권한 및 실시간 데이터 동작을 검증해 확정합니다.

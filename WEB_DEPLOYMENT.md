# Flutter 웹 빌드와 서버 배포 분리

## GitHub Actions
`build_web_release`를 main 변경 시 자동 실행하거나 Actions에서 수동 실행합니다.
Flutter 빌드 후 GHCR에 `ghcr.io/${GITHUB_REPOSITORY,,}-web` 이미지를 게시합니다.
태그는 브랜치명(main)과 `sha-커밋SHA`입니다. 수동 실행도 배포할 브랜치를 명시합니다.
동일 브랜치 실행은 순서대로 처리하여 이전 빌드가 최신 태그를 덮어쓰지 않습니다.
Actions Variables 변경만으로 실행되지는 않으므로 변경 후 수동 실행합니다.
기존 Android·Toss 빌드와 별개입니다.

Repository Variables:
- `FLUTTER_VERSION`: 사용할 Flutter 버전. 비우면 stable.
- `WEB_BASE_HREF`: / (시작·끝 / 필수)
- `BUS_API_URL`: 공개 버스 API 주소 (기본 https://bustimer.bluewaikiki.top)

웹에 포함되는 값은 공개 정보입니다. DB 비밀번호·관리자 토큰은 서버 .env에서만 관리합니다.
GHCR 게시에는 내장 GITHUB_TOKEN의 packages:write 권한을 사용합니다.

## 서버 전환
1. PR 병합 후 Actions 성공 및 GHCR 이미지 생성을 먼저 확인합니다.
2. 비공개 패키지는 서버에서 read:packages 권한 토큰으로 `docker login ghcr.io`를 한 번 수행합니다. 토큰을 저장소에 넣지 않습니다.
3. 기존 build/web 바인드 마운트가 제거되고 web 컨테이너가 API와 분리됩니다. 공통 Caddy 주소 bus-api:18082는 web 컨테이너가 이어받으며 /api/* 및 /health는 기존 bustimer로 전달합니다.
4. 기존 Compose 프로젝트명과 운영 파일 목록, DB 볼륨을 그대로 사용합니다.
5. 웹 배포:
```bash
cd /home/mins/source/busstop_timer/server
compose=(docker compose -p busstop_timer -f compose.yaml -f compose.proxy.yaml)
"${compose[@]}" pull web
"${compose[@]}" up -d --no-deps --wait web
```
최초 전환은 API와 DB도 먼저 기동되어 있어야 합니다. 기존 server/deploy/deploy.sh는 초기 환경 준비와 전체 기동을 지원하지만 Flutter는 실행하지 않습니다.

Compose 환경변수:
- `WEB_IMAGE`: 기본 ghcr.io/bluehawhy/busstop_timer-web
- `WEB_IMAGE_TAG`: 기본 main. 재현 가능한 배포·롤백은 sha-커밋SHA를 사용합니다.
- `WEB_PORT`: 기본 18082 (loopback 바인딩)

이미지 pull 실패 시 기존 컨테이너를 교체하지 않습니다. DB 볼륨 삭제는 필요 없습니다.
API만 업데이트: 위 compose 배열로 `up -d --build --no-deps --wait bustimer`를 실행합니다.
대시보드에 프로젝트 이름에 따른 분기는 추가하지 않습니다. Compose의 image/pull_policy/build 정의를 따릅니다.
서버 .env 변경은 웹의 빌드 설정에 반영되지 않습니다. 웹 설정은 Actions Variables 변경 후 재빌드합니다.

실제 서버 전환·이미지 다운로드는 PR과 별도이며 아직 수행하지 않았습니다.

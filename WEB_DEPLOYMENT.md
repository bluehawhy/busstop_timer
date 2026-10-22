# 웹 자동 배포와 API 서버 업데이트

## 변경 반영 방식
- 웹 소스 변경: main push → GitHub 호스팅 runner에서 Flutter 및 웹 이미지 빌드 → GHCR 게시 → 배포 전용 runner에서 웹만 교체.
- API 소스 변경: 웹 workflow의 paths에 해당하지 않아 웹을 빌드하지 않습니다. 대시보드의 Compose 업데이트로 API 서버만 build/교체합니다.
- 두 영역 변경: 웹은 Actions에서, API는 대시보드에서 각각 반영합니다.
- 웹 배포는 API·DB를 재생성하지 않습니다. 대시보드의 API 업데이트도 웹·DB를 재생성하지 않습니다.

## 한 번만 설정
홈서버에서 이 저장소를 사용할 GitHub self-hosted runner를 등록하고 서비스로 실행합니다. 저장소 Settings → Actions → Runners → New self-hosted runner의 Linux x64 안내를 따르세요. 두 비공개 저장소 모두 등록하며 같은 홈서버에서 사용할 수 있습니다.
runner 사용자에게 Docker 실행 권한과 기존 프로젝트 Compose 파일 읽기/쓰기 권한이 필요합니다. 추가 사용자 라벨은 `web-deploy`로 지정합니다.
Flutter 빌드는 GitHub 호스팅 runner에서만 수행하고 홈서버 runner는 이미지 다운로드와 웹 교체만 실행합니다.

Repository Variables:
- `WEB_DEPLOY_DIR`: 기존 운영 Compose의 작업 경로. 예: /home/mins/source/busstop_timer/server
- `WEB_DEPLOY_ENV_FILE`: 필요한 경우 Compose 환경 파일 절대 경로. 여러 파일은 쉼표 구분. 비우면 실행 중 컨테이너의 Compose 환경 파일 메타데이터 또는 기본 .env를 사용합니다.
- `FLUTTER_VERSION`: Flutter 버전. 비우면 stable.
- `WEB_BASE_HREF`: /
- `BUS_API_URL`: 공개 API 주소 (기본 https://bustimer.bluewaikiki.top)

GHCR 인증은 Actions 내장 GITHUB_TOKEN을 배포 job에 전달하며 임시 Docker 설정은 종료 시 삭제합니다. SSH 포트를 추가로 공개할 필요가 없습니다. 빌드 설정에는 공개 정보만 넣습니다. DB 비밀번호·인증 토큰은 서버에서 관리합니다.

## 최초 전환
서버에 이 PR의 Compose 설정과 .gitignore를 먼저 적용합니다. API와 DB가 실행 중이고 모든 컨테이너가 같은 프로젝트명·호환되는 Compose 파일 목록을 사용해야 합니다.
기존 build/web 바인드 마운트는 제거됩니다. web 컨테이너가 bus-api:18082 주소를 이어받고 /api/*와 /health를 bustimer API에 전달합니다.

이후 Actions의 build_web_release_and_deploy를 main에서 실행합니다. 웹 빌드뿐 아니라 deploy job까지 성공해야 배포 완료입니다. 배포 runner가 없으면 deploy job은 대기하고 실제 서비스는 기존 버전입니다.

## 배포 상태
이미지는 가변 main 태그가 아니라 해당 빌드가 반환한 immutable digest로 배포합니다.
서버의 Compose 작업 경로에 생성하는 `.web-image.compose.json`이 현재 digest를 보관합니다. 이 파일은 Git에서 제외하며 이후 Compose 작업에도 적용됩니다.
실행 중인 컨테이너 label에서 기존 프로젝트명과 전체 운영 Compose 파일 목록을 읽습니다. DB 볼륨과 다른 서비스는 변경하지 않습니다.
웹/API 배포가 겹치면 같은 프로젝트 잠금을 확인해 중단하므로 완료 후 재실행합니다.

이미지 다운로드가 실패하면 실행 중인 웹을 교체하지 않습니다. 컨테이너 교체·헬스 확인 실패 시 Actions가 실패하고 이전 이미지 설정 파일을 복원하지만 컨테이너 자동 롤백을 보장하지는 않습니다. 서버 상태를 확인해야 합니다.
웹 배포 runner의 로그는 Actions deploy job에서 확인합니다. API 업데이트 상태·로그는 대시보드에서 확인합니다.

서버 runner 등록과 Variables 설정 및 실제 서버 전환은 코드 변경과 별도이며 아직 수행하지 않았습니다.

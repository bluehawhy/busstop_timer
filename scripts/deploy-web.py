#!/usr/bin/env python3
"""Deploy a CI-built web image on the self-hosted deployment runner."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def output(command, *, cwd=None, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('배포 설정을 확인할 수 없습니다. 서버의 Compose 환경설정을 확인하세요.')
    return result.stdout


def run(command, *, cwd, env):
    # Compose output may include interpolated secrets. Keep only step summaries.
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('배포 명령이 실패했습니다. 서버의 Docker 상태와 GHCR 접근 권한을 확인하세요.')


def main():
    directory = os.environ.get('WEB_DEPLOY_DIR', '').strip()
    if not directory:
        raise RuntimeError('Repository Variable WEB_DEPLOY_DIR에 서버의 Compose 작업 경로를 설정하세요.')
    root = Path(directory).resolve(strict=True)
    image = os.environ.get('WEB_DEPLOY_IMAGE', '')
    if not re.fullmatch(r'ghcr\.io/[a-z0-9_./-]+@sha256:[0-9a-f]{64}', image):
        raise RuntimeError('빌드 job이 반환한 GHCR 이미지 digest가 필요합니다.')
    repository = Path(output(['git', '-C', str(root), 'rev-parse', '--show-toplevel']).strip()).resolve()
    lock_dir = repository.parent / '.bluewaikiki-deploy-locks'
    lock_dir.mkdir(mode=0o700, exist_ok=True)
    lock_path = lock_dir / (hashlib.sha256(str(root).encode()).hexdigest() + '.lock')
    with lock_path.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('같은 프로젝트의 API 또는 웹 배포가 진행 중입니다. Actions를 다시 실행하세요.')
        deploy(root, image)


def deploy(root, image):
    ids = output(['docker', 'ps', '-aq']).split()
    rows = json.loads(output(['docker', 'inspect', *ids])) if ids else []
    labels = [row['Config'].get('Labels') or {} for row in rows]
    labels = [label for label in labels if label.get('com.docker.compose.project.working_dir') and
              Path(label['com.docker.compose.project.working_dir']).resolve() == root]
    projects = {label.get('com.docker.compose.project') for label in labels}
    if len(projects) != 1:
        raise RuntimeError('설정한 경로에서 하나의 기존 Compose 프로젝트를 찾을 수 없습니다. 최초 Compose 구성을 먼저 적용하세요.')
    project = projects.pop()
    configurations = [label.get('com.docker.compose.project.config_files', '').split(',') for label in labels]
    files = max(configurations, key=len)
    if not all(config == files[:len(config)] for config in configurations) or not all(Path(path).is_file() for path in files):
        raise RuntimeError('운영 Compose 파일 목록이 일치하지 않습니다.')
    override = root / '.web-image.compose.json'
    files = [path for path in files if Path(path).resolve() != override]
    command = ['docker', 'compose', '--project-name', project, '--project-directory', str(root)]
    env_files = os.environ.get('WEB_DEPLOY_ENV_FILE', '').strip()
    if not env_files:
        env_files = next((label.get('com.docker.compose.project.environment_file', '') for label in labels
                          if label.get('com.docker.compose.project.environment_file')), '')
    for path in filter(None, env_files.split(',')):
        if not Path(path).is_file():
            raise RuntimeError('Compose 환경변수 파일을 찾을 수 없습니다.')
        command += ['--env-file', path]
    for path in files:
        command += ['--file', path]
    base_env = {**os.environ, 'COMPOSE_ANSI': 'never'}
    config = json.loads(output(command + ['config', '--format', 'json'], cwd=root, env=base_env))
    services = [name for name, spec in config.get('services', {}).items()
                if (spec.get('labels') or {}).get('top.bluewaikiki.deploy.role') == 'web'
                and spec.get('image') and not spec.get('build')]
    if len(services) != 1:
        raise RuntimeError('image로 실행하는 web 역할 서비스가 정확히 하나 필요합니다.')
    service = services[0]
    with tempfile.TemporaryDirectory(prefix='web-deploy-docker-') as temporary:
        env = {**base_env, 'DOCKER_CONFIG': temporary}
        token = os.environ.get('GHCR_TOKEN', '')
        user = os.environ.get('GHCR_USER', '')
        if not token or not user:
            raise RuntimeError('Actions GHCR 인증 정보를 확인하세요.')
        login = subprocess.run(['docker', 'login', 'ghcr.io', '--username', user, '--password-stdin'],
                               input=token, text=True, capture_output=True, env=env)
        if login.returncode:
            raise RuntimeError('GHCR 인증에 실패했습니다.')
        print('완성된 웹 이미지 다운로드', flush=True)
        run(['docker', 'pull', image], cwd=root, env=env)
        previous = override.read_bytes() if override.exists() else None
        document = {'services': {service: {'image': image}}}
        # Retain the selected digest across future Compose operations.
        with tempfile.NamedTemporaryFile(mode='w', dir=root, prefix='.web-image-', delete=False) as stream:
            staged = Path(stream.name)
            json.dump(document, stream)
        staged.replace(override)
        try:
            print('웹 서비스만 교체 (API·DB 유지)', flush=True)
            run(command + ['--file', str(override), 'up', '--detach', '--no-deps', '--no-build',
                           '--pull', 'never', '--wait', '--wait-timeout', '180', service], cwd=root, env=env)
        except Exception:
            if previous is None:
                override.unlink(missing_ok=True)
            else:
                override.write_bytes(previous)
            print('배포 실패: 이전 이미지 설정을 복원했습니다. 실행 중인 웹 컨테이너 상태를 확인하세요.', flush=True)
            raise
        print('웹 배포 완료: ' + image, flush=True)


if __name__ == '__main__':
    main()

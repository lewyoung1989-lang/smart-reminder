# Tencent Cloud Single-Server Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the existing reminder MVP to one Tencent Cloud Ubuntu server behind HTTPS at `aipupu.cloud`, with private application dependencies, repeatable releases, backups, and rollback instructions.

**Architecture:** Keep local development in `compose.yaml` and add a production Compose overlay under `deploy/tencent/`. Nginx terminates TLS, Django/Gunicorn serves the API on the private Compose network, PostgreSQL and Redis remain private, and shell scripts enforce clean Git revisions, validated environment files, migrations, health checks, and backups. Medicine OCR remains owned by its separate branch and is not changed in this plan.

**Tech Stack:** Ubuntu, Docker Engine, Docker Compose v2.24.4+, Nginx 1.27, Certbot, Django 5.2, Gunicorn, Celery 5.5, PostgreSQL 16, Redis 7, pytest, Bash, Python 3.

---

## Scope And File Map

Files created or modified by this plan:

- `backend/config/settings.py`: environment-driven production proxy, host, CSRF, cookie, redirect, and HSTS settings.
- `backend/tests/deployment/test_production_settings.py`: isolated production-settings contract.
- `backend/tests/deployment/test_env_contract.py`: production environment and validator contract.
- `backend/tests/deployment/test_compose_contract.py`: production Compose and Nginx exposure contract.
- `backend/tests/deployment/test_operations_scripts.py`: release and backup script safety contract.
- `backend/requirements/dev.txt`: add PyYAML for Compose contract tests only.
- `deploy/tencent/env.production.example`: secret-free production variable template.
- `deploy/tencent/compose.production.yaml`: production-only service overrides and ingress services.
- `deploy/tencent/nginx/bootstrap.conf`: ACME-only HTTP ingress used before a certificate exists.
- `deploy/tencent/nginx/aipupu.cloud.conf`: HTTPS proxy, HTTP redirect, headers, and ACME path.
- `deploy/tencent/scripts/check_env.py`: structured environment-file validation without sourcing shell code.
- `deploy/tencent/scripts/bootstrap_tls.sh`: first certificate issuance.
- `deploy/tencent/scripts/deploy.sh`: clean-revision build, migration, startup, and health check.
- `deploy/tencent/scripts/backup_postgres.sh`: compressed daily backup and retention.
- `deploy/tencent/scripts/restore_postgres.sh`: explicit, confirmed restore.
- `deploy/tencent/README.md`: host initialization, release, rollback, backup, and incident runbook.
- `README.md`: production deployment link and public health URL.
- `Makefile`: local deployment-contract test target.

Do not modify `backend/apps/ocr/`, `backend/apps/medicines/`, `backend/requirements/ocr.txt`, `app/lib/features/medicine_ocr/`, or OCR sections added by the parallel branch.

## Task 1: Add Environment-Driven Django Production Security

**Files:**
- Modify: `backend/config/settings.py`
- Create: `backend/tests/deployment/test_production_settings.py`

- [ ] **Step 1: Write the failing subprocess settings test**

```python
# backend/tests/deployment/test_production_settings.py
import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


def test_production_settings_trust_only_https_proxy_and_domain():
    environment = os.environ.copy()
    environment.update(
        {
            "DJANGO_DEBUG": "false",
            "DJANGO_ALLOWED_HOSTS": "aipupu.cloud",
            "DJANGO_CSRF_TRUSTED_ORIGINS": "https://aipupu.cloud",
            "DJANGO_SECURE_SSL_REDIRECT": "true",
            "DJANGO_SECURE_HSTS_SECONDS": "3600",
        }
    )
    code = """
from config import settings
assert settings.DEBUG is False
assert settings.ALLOWED_HOSTS == ["aipupu.cloud"]
assert settings.CSRF_TRUSTED_ORIGINS == ["https://aipupu.cloud"]
assert settings.SECURE_PROXY_SSL_HEADER == ("HTTP_X_FORWARDED_PROTO", "https")
assert settings.SECURE_SSL_REDIRECT is True
assert settings.SESSION_COOKIE_SECURE is True
assert settings.CSRF_COOKIE_SECURE is True
assert settings.SECURE_HSTS_SECONDS == 3600
"""
    result = subprocess.run(
        [sys.executable, "-c", code],
        cwd=REPO_ROOT / "backend",
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `.venv/bin/pytest backend/tests/deployment/test_production_settings.py -q`

Expected: FAIL because `CSRF_TRUSTED_ORIGINS` and the proxy/security settings are absent.

- [ ] **Step 3: Add minimal production settings**

Add this helper near the top of `backend/config/settings.py`:

```python
def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    return default if value is None else value.lower() == "true"
```

Replace the current `DEBUG` expression and extend host/security configuration:

```python
DEBUG = env_bool("DJANGO_DEBUG", True)
ALLOWED_HOSTS = [
    host.strip()
    for host in os.environ.get(
        "DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1,testserver"
    ).split(",")
    if host.strip()
]
CSRF_TRUSTED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("DJANGO_CSRF_TRUSTED_ORIGINS", "").split(",")
    if origin.strip()
]
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", False)
SESSION_COOKIE_SECURE = env_bool("DJANGO_SESSION_COOKIE_SECURE", not DEBUG)
CSRF_COOKIE_SECURE = env_bool("DJANGO_CSRF_COOKIE_SECURE", not DEBUG)
SECURE_HSTS_SECONDS = int(os.environ.get("DJANGO_SECURE_HSTS_SECONDS", "0"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = env_bool("DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS", False)
SECURE_HSTS_PRELOAD = env_bool("DJANGO_SECURE_HSTS_PRELOAD", False)
```

Do not enable HSTS preload during the first deployment. The production environment starts with `3600` seconds and increases only after HTTPS renewal is proven.

- [ ] **Step 4: Verify focused and existing backend tests**

Run: `.venv/bin/pytest backend/tests/deployment/test_production_settings.py backend/tests/core/test_health.py -q`

Expected: `2 passed`.

- [ ] **Step 5: Commit Django production security**

```bash
git add backend/config/settings.py backend/tests/deployment/test_production_settings.py
git commit -m "feat: harden Django production settings"
```

## Task 2: Define And Validate The Production Environment

**Files:**
- Create: `deploy/tencent/env.production.example`
- Create: `deploy/tencent/scripts/check_env.py`
- Create: `backend/tests/deployment/test_env_contract.py`

- [ ] **Step 1: Write failing environment contract tests**

```python
# backend/tests/deployment/test_env_contract.py
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
EXAMPLE = REPO_ROOT / "deploy/tencent/env.production.example"
VALIDATOR = REPO_ROOT / "deploy/tencent/scripts/check_env.py"


def test_example_lists_required_production_variables_without_secrets():
    values = {}
    for raw_line in EXAMPLE.read_text().splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    assert values["DOMAIN"] == "aipupu.cloud"
    assert values["DJANGO_DEBUG"] == "false"
    assert values["DJANGO_ALLOWED_HOSTS"] == "aipupu.cloud"
    assert values["DJANGO_CSRF_TRUSTED_ORIGINS"] == "https://aipupu.cloud"
    for secret in ("DJANGO_SECRET_KEY", "POSTGRES_PASSWORD", "DEEPSEEK_API_KEY", "CERTBOT_EMAIL"):
        assert values[secret] == ""


def test_validator_rejects_missing_secrets(tmp_path):
    env_file = tmp_path / "production.env"
    env_file.write_text(EXAMPLE.read_text())
    result = subprocess.run(
        [sys.executable, str(VALIDATOR), str(env_file)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert "DJANGO_SECRET_KEY" in result.stderr
    assert "POSTGRES_PASSWORD" in result.stderr
    assert "DEEPSEEK_API_KEY" in result.stderr
    assert "CERTBOT_EMAIL" in result.stderr


def test_validator_reads_a_value_without_shell_evaluation(tmp_path):
    content = EXAMPLE.read_text()
    content = content.replace("DJANGO_SECRET_KEY=\n", "DJANGO_SECRET_KEY=test-secret\n")
    content = content.replace("POSTGRES_PASSWORD=\n", "POSTGRES_PASSWORD=test-password\n")
    content = content.replace("DEEPSEEK_API_KEY=\n", "DEEPSEEK_API_KEY=test-key\n")
    content = content.replace("CERTBOT_EMAIL=\n", "CERTBOT_EMAIL=owner@example.com\n")
    env_file = tmp_path / "production.env"
    env_file.write_text(content)
    result = subprocess.run(
        [sys.executable, str(VALIDATOR), str(env_file), "--get", "DOMAIN"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "aipupu.cloud"
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `.venv/bin/pytest backend/tests/deployment/test_env_contract.py -q`

Expected: FAIL because the environment template and validator do not exist.

- [ ] **Step 3: Add the secret-free environment template**

```dotenv
# deploy/tencent/env.production.example
DOMAIN=aipupu.cloud
APP_VERSION=
DJANGO_SECRET_KEY=
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=aipupu.cloud
DJANGO_CSRF_TRUSTED_ORIGINS=https://aipupu.cloud
DJANGO_SECURE_SSL_REDIRECT=true
DJANGO_SECURE_HSTS_SECONDS=3600
DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS=false
DJANGO_SECURE_HSTS_PRELOAD=false
POSTGRES_DB=smart_reminder
POSTGRES_USER=smart_reminder
POSTGRES_PASSWORD=
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/1
DEEPSEEK_API_KEY=
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
DEEPSEEK_TIMEOUT_SECONDS=8
CERTBOT_EMAIL=
BACKUP_DIR=/opt/smart-reminder/backups/postgres
BACKUP_RETENTION_DAYS=14
```

- [ ] **Step 4: Implement structured validation without sourcing the file**

```python
#!/usr/bin/env python3
# deploy/tencent/scripts/check_env.py
import sys
from pathlib import Path


REQUIRED = {
    "DOMAIN",
    "DJANGO_SECRET_KEY",
    "DJANGO_DEBUG",
    "DJANGO_ALLOWED_HOSTS",
    "DJANGO_CSRF_TRUSTED_ORIGINS",
    "POSTGRES_DB",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "CELERY_BROKER_URL",
    "CELERY_RESULT_BACKEND",
    "DEEPSEEK_API_KEY",
    "CERTBOT_EMAIL",
    "BACKUP_DIR",
    "BACKUP_RETENTION_DAYS",
}


def parse_env(path: Path) -> dict[str, str]:
    values = {}
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"line {line_number} must use KEY=VALUE")
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def validate(values: dict[str, str]) -> list[str]:
    errors = [f"{key} is required" for key in sorted(REQUIRED) if not values.get(key)]
    if values.get("DOMAIN") not in {None, "", "aipupu.cloud"}:
        errors.append("DOMAIN must be aipupu.cloud")
    if values.get("DJANGO_DEBUG") not in {None, "", "false"}:
        errors.append("DJANGO_DEBUG must be false")
    if values.get("DJANGO_SECURE_SSL_REDIRECT") not in {None, "", "true"}:
        errors.append("DJANGO_SECURE_SSL_REDIRECT must be true")
    return errors


def main() -> int:
    if len(sys.argv) not in {2, 4} or (len(sys.argv) == 4 and sys.argv[2] != "--get"):
        print("usage: check_env.py ENV_FILE [--get KEY]", file=sys.stderr)
        return 2
    try:
        values = parse_env(Path(sys.argv[1]))
        errors = validate(values)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    if len(sys.argv) == 4:
        key = sys.argv[3]
        if key not in values:
            print(f"{key} is not defined", file=sys.stderr)
            return 2
        print(values[key])
        return 0
    print("Production environment is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Run the environment tests**

Run: `.venv/bin/pytest backend/tests/deployment/test_env_contract.py -q`

Expected: `3 passed`.

- [ ] **Step 6: Commit the production environment contract**

```bash
git add deploy/tencent/env.production.example deploy/tencent/scripts/check_env.py backend/tests/deployment/test_env_contract.py
git commit -m "ops: validate Tencent production environment"
```

## Task 3: Add Private Production Compose And Nginx TLS Ingress

**Files:**
- Modify: `backend/requirements/dev.txt`
- Create: `deploy/tencent/compose.production.yaml`
- Create: `deploy/tencent/nginx/bootstrap.conf`
- Create: `deploy/tencent/nginx/aipupu.cloud.conf`
- Create: `backend/tests/deployment/test_compose_contract.py`

- [ ] **Step 1: Add PyYAML to development requirements**

Append `PyYAML==6.0.2` to `backend/requirements/dev.txt`, then run:

`.venv/bin/python -m pip install PyYAML==6.0.2`

Expected: installation exits `0`; no production requirement changes.

- [ ] **Step 2: Write failing Compose and Nginx contract tests**

```python
# backend/tests/deployment/test_compose_contract.py
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]


class ComposeLoader(yaml.SafeLoader):
    pass


ComposeLoader.add_constructor("!reset", lambda loader, node: [])


def load_production_compose():
    path = REPO_ROOT / "deploy/tencent/compose.production.yaml"
    return yaml.load(path.read_text(), Loader=ComposeLoader)


def test_internal_services_publish_no_host_ports():
    services = load_production_compose()["services"]
    for name in ("postgres", "redis", "minio", "api"):
        assert services[name]["ports"] == []
    assert services["nginx"]["ports"] == ["80:80", "443:443"]


def test_production_services_restart_and_rotate_logs():
    services = load_production_compose()["services"]
    for name in ("postgres", "redis", "api", "worker", "beat", "nginx"):
        assert services[name]["restart"] == "unless-stopped"
        assert services[name]["logging"]["options"] == {"max-size": "10m", "max-file": "5"}


def test_nginx_redirects_http_and_forwards_https_metadata():
    config = (REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf").read_text()
    assert "return 301 https://$host$request_uri;" in config
    assert "ssl_certificate /etc/letsencrypt/live/aipupu.cloud/fullchain.pem;" in config
    assert "proxy_pass http://api:8000;" in config
    assert "proxy_set_header X-Forwarded-Proto https;" in config
    assert "proxy_set_header Authorization $http_authorization;" in config
```

- [ ] **Step 3: Run the contract test and verify RED**

Run: `.venv/bin/pytest backend/tests/deployment/test_compose_contract.py -q`

Expected: FAIL because the production Compose and Nginx files do not exist.

- [ ] **Step 4: Add the production Compose overlay**

Create `deploy/tencent/compose.production.yaml` with these service rules:

```yaml
x-logging: &production_logging
  driver: json-file
  options:
    max-size: 10m
    max-file: "5"

x-backend-environment: &production_backend_environment
  DJANGO_SECRET_KEY: ${DJANGO_SECRET_KEY:?DJANGO_SECRET_KEY is required}
  DJANGO_DEBUG: ${DJANGO_DEBUG:-false}
  DJANGO_ALLOWED_HOSTS: ${DJANGO_ALLOWED_HOSTS:-aipupu.cloud}
  DJANGO_CSRF_TRUSTED_ORIGINS: ${DJANGO_CSRF_TRUSTED_ORIGINS:-https://aipupu.cloud}
  DJANGO_SECURE_SSL_REDIRECT: ${DJANGO_SECURE_SSL_REDIRECT:-true}
  DJANGO_SECURE_HSTS_SECONDS: ${DJANGO_SECURE_HSTS_SECONDS:-3600}
  DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS: ${DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS:-false}
  DJANGO_SECURE_HSTS_PRELOAD: ${DJANGO_SECURE_HSTS_PRELOAD:-false}
  POSTGRES_DB: ${POSTGRES_DB:-smart_reminder}
  POSTGRES_USER: ${POSTGRES_USER:-smart_reminder}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}
  POSTGRES_HOST: postgres
  POSTGRES_PORT: "5432"
  CELERY_BROKER_URL: ${CELERY_BROKER_URL:-redis://redis:6379/0}
  CELERY_RESULT_BACKEND: ${CELERY_RESULT_BACKEND:-redis://redis:6379/1}
  DEEPSEEK_API_KEY: ${DEEPSEEK_API_KEY:?DEEPSEEK_API_KEY is required}
  DEEPSEEK_BASE_URL: ${DEEPSEEK_BASE_URL:-https://api.deepseek.com}
  DEEPSEEK_MODEL: ${DEEPSEEK_MODEL:-deepseek-v4-flash}
  DEEPSEEK_TIMEOUT_SECONDS: ${DEEPSEEK_TIMEOUT_SECONDS:-8}

services:
  postgres:
    ports: !reset []
    restart: unless-stopped
    logging: *production_logging

  redis:
    ports: !reset []
    restart: unless-stopped
    logging: *production_logging

  minio:
    ports: !reset []
    profiles: [local-storage]
    restart: unless-stopped
    logging: *production_logging

  api:
    image: smart-reminder-api:${APP_VERSION:?APP_VERSION is required}
    ports: !reset []
    environment: *production_backend_environment
    command: gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 2 --timeout 30
    restart: unless-stopped
    logging: *production_logging
    healthcheck:
      test:
        - CMD
        - python
        - -c
        - "import urllib.request; request=urllib.request.Request('http://127.0.0.1:8000/api/v1/health', headers={'X-Forwarded-Proto':'https'}); assert urllib.request.urlopen(request, timeout=3).status == 200"
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 20s

  worker:
    image: smart-reminder-api:${APP_VERSION:?APP_VERSION is required}
    environment: *production_backend_environment
    command: celery -A config worker -Q celery --loglevel=INFO
    restart: unless-stopped
    logging: *production_logging

  beat:
    image: smart-reminder-api:${APP_VERSION:?APP_VERSION is required}
    environment: *production_backend_environment
    restart: unless-stopped
    logging: *production_logging

  nginx-bootstrap:
    image: nginx:1.27-alpine
    profiles: [bootstrap]
    ports:
      - "80:80"
    volumes:
      - ./deploy/tencent/nginx/bootstrap.conf:/etc/nginx/conf.d/default.conf:ro
      - certbot_www:/var/www/certbot:ro
    restart: unless-stopped
    logging: *production_logging

  nginx:
    image: nginx:1.27-alpine
    profiles: [production]
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./deploy/tencent/nginx/aipupu.cloud.conf:/etc/nginx/conf.d/default.conf:ro
      - certbot_www:/var/www/certbot:ro
      - certbot_etc:/etc/letsencrypt:ro
    depends_on:
      api:
        condition: service_healthy
    restart: unless-stopped
    logging: *production_logging

  certbot:
    image: certbot/certbot:v4.1.1
    profiles: [certbot]
    volumes:
      - certbot_www:/var/www/certbot
      - certbot_etc:/etc/letsencrypt

volumes:
  certbot_www:
  certbot_etc:
```

Require Docker Compose v2.24.4 or newer because the overlay uses the `!reset` tag.

- [ ] **Step 5: Add bootstrap and HTTPS Nginx configuration**

`bootstrap.conf` serves only `/.well-known/acme-challenge/` and returns `503` for every other path. `aipupu.cloud.conf` must contain:

```nginx
server {
    listen 80;
    server_name aipupu.cloud;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name aipupu.cloud;

    ssl_certificate /etc/letsencrypt/live/aipupu.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/aipupu.cloud/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    client_max_body_size 2m;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;

    location / {
        proxy_pass http://api:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Authorization $http_authorization;
        proxy_connect_timeout 5s;
        proxy_read_timeout 35s;
    }
}
```

- [ ] **Step 6: Run contract tests**

Run: `.venv/bin/pytest backend/tests/deployment/test_compose_contract.py -q`

Expected: `3 passed`.

Run when Docker Compose is available:

```bash
docker compose --env-file /tmp/smart-reminder-production.env \
  -f compose.yaml -f deploy/tencent/compose.production.yaml config --quiet
```

Expected: exit `0`. Create the temporary file by copying the example and using non-production test values; delete it after validation and never place it in the repository.

- [ ] **Step 7: Commit production ingress and Compose**

```bash
git add backend/requirements/dev.txt backend/tests/deployment/test_compose_contract.py deploy/tencent/compose.production.yaml deploy/tencent/nginx
git commit -m "ops: add private Tencent production stack"
```

## Task 4: Add Repeatable TLS Bootstrap And Release Scripts

**Files:**
- Create: `deploy/tencent/scripts/bootstrap_tls.sh`
- Create: `deploy/tencent/scripts/deploy.sh`
- Create: `backend/tests/deployment/test_operations_scripts.py`

- [ ] **Step 1: Write failing script safety tests**

```python
# backend/tests/deployment/test_operations_scripts.py
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = REPO_ROOT / "deploy/tencent/scripts"


def test_release_scripts_are_valid_bash():
    for name in ("bootstrap_tls.sh", "deploy.sh"):
        result = subprocess.run(
            ["bash", "-n", str(SCRIPTS / name)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr


def test_deploy_requires_clean_expected_revision_and_health_check():
    script = (SCRIPTS / "deploy.sh").read_text()
    assert "git diff --quiet" in script
    assert "git diff --cached --quiet" in script
    assert "EXPECTED_SHA" in script
    assert "manage.py migrate --noinput" in script
    assert "/api/v1/health" in script
    assert "--profile production" in script


def test_tls_bootstrap_uses_webroot_and_never_starts_plain_http_api():
    script = (SCRIPTS / "bootstrap_tls.sh").read_text()
    assert "certonly" in script
    assert "--webroot" in script
    assert "nginx-bootstrap" in script
    assert "up -d api" not in script
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `.venv/bin/pytest backend/tests/deployment/test_operations_scripts.py -q`

Expected: FAIL because the scripts do not exist.

- [ ] **Step 3: Implement `bootstrap_tls.sh`**

The script accepts an environment path, runs `check_env.py`, builds the shared Compose argument array, starts only `nginx-bootstrap`, obtains a certificate with Certbot Webroot using `DOMAIN` and `CERTBOT_EMAIL`, and always stops the bootstrap container through an `EXIT` trap. It must not start Django on plain HTTP.

Core commands:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ENV_FILE=${1:?usage: bootstrap_tls.sh ENV_FILE}
python3 "$ROOT_DIR/deploy/tencent/scripts/check_env.py" "$ENV_FILE"
DOMAIN=$(python3 "$ROOT_DIR/deploy/tencent/scripts/check_env.py" "$ENV_FILE" --get DOMAIN)
CERTBOT_EMAIL=$(python3 "$ROOT_DIR/deploy/tencent/scripts/check_env.py" "$ENV_FILE" --get CERTBOT_EMAIL)
export APP_VERSION=bootstrap

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/compose.yaml" -f "$ROOT_DIR/deploy/tencent/compose.production.yaml")
cleanup() { "${COMPOSE[@]}" --profile bootstrap stop nginx-bootstrap >/dev/null 2>&1 || true; }
trap cleanup EXIT

"${COMPOSE[@]}" --profile bootstrap up -d nginx-bootstrap
"${COMPOSE[@]}" --profile certbot run --rm certbot certonly \
  --webroot --webroot-path /var/www/certbot \
  --domain "$DOMAIN" --email "$CERTBOT_EMAIL" \
  --agree-tos --no-eff-email --non-interactive
```

Do not `source` the environment file. Docker Compose reads it through `--env-file`; the shell receives only the explicitly requested control values.

- [ ] **Step 4: Implement `deploy.sh`**

The script accepts `EXPECTED_SHA` and `ENV_FILE`, validates the environment, requires an exact clean Git revision, exports the 12-character `APP_VERSION`, validates Compose, builds the API image, starts PostgreSQL and Redis, runs migrations in a one-shot API container, starts API/Worker/Beat, waits for the API health check, and finally starts the production Nginx profile.

Use these commands and fail immediately on any nonzero status:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
EXPECTED_SHA=${1:?usage: deploy.sh EXPECTED_SHA ENV_FILE}
ENV_FILE=${2:?usage: deploy.sh EXPECTED_SHA ENV_FILE}

cd "$ROOT_DIR"
python3 deploy/tencent/scripts/check_env.py "$ENV_FILE"
ACTUAL_SHA=$(git rev-parse HEAD)
EXPECTED_FULL=$(git rev-parse --verify "${EXPECTED_SHA}^{commit}")
[[ "$ACTUAL_SHA" == "$EXPECTED_FULL" ]] || { echo "HEAD does not match EXPECTED_SHA" >&2; exit 1; }
git diff --quiet
git diff --cached --quiet
export APP_VERSION
APP_VERSION=$(git rev-parse --short=12 HEAD)

COMPOSE=(docker compose --env-file "$ENV_FILE" -f compose.yaml -f deploy/tencent/compose.production.yaml)
"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" build api
"${COMPOSE[@]}" up -d postgres redis
"${COMPOSE[@]}" run --rm api python manage.py migrate --noinput
"${COMPOSE[@]}" up -d api worker beat

for attempt in $(seq 1 24); do
  if "${COMPOSE[@]}" exec -T api python -c "import urllib.request; request=urllib.request.Request('http://127.0.0.1:8000/api/v1/health', headers={'X-Forwarded-Proto':'https'}); assert urllib.request.urlopen(request, timeout=3).status == 200"; then
    "${COMPOSE[@]}" --profile production up -d nginx
    exit 0
  fi
  sleep 5
done
echo "API health check failed" >&2
exit 1
```

Do not add automatic destructive rollback or volume deletion.

- [ ] **Step 5: Run the script safety tests**

Run: `.venv/bin/pytest backend/tests/deployment/test_operations_scripts.py -q`

Expected: `3 passed`.

- [ ] **Step 6: Commit release automation**

```bash
git add deploy/tencent/scripts/bootstrap_tls.sh deploy/tencent/scripts/deploy.sh backend/tests/deployment/test_operations_scripts.py
git commit -m "ops: automate TLS bootstrap and releases"
```

## Task 5: Add PostgreSQL Backup And Explicit Restore

**Files:**
- Modify: `deploy/tencent/scripts/check_env.py`
- Create: `deploy/tencent/scripts/backup_postgres.sh`
- Create: `deploy/tencent/scripts/restore_postgres.sh`
- Modify: `backend/tests/deployment/test_operations_scripts.py`

- [ ] **Step 1: Add failing backup and restore safety tests**

Append:

```python
def test_backup_is_private_compressed_and_retained():
    script = (SCRIPTS / "backup_postgres.sh").read_text()
    assert "pg_dump" in script
    assert "--format=custom" in script
    assert "chmod 600" in script
    assert "BACKUP_RETENTION_DAYS" in script
    assert "-mtime" in script


def test_restore_requires_confirmation_and_explicit_file():
    script = (SCRIPTS / "restore_postgres.sh").read_text()
    assert "BACKUP_FILE" in script
    assert "RESTORE" in script
    assert "pg_restore" in script
    assert "--clean" not in script
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `.venv/bin/pytest backend/tests/deployment/test_operations_scripts.py -q`

Expected: FAIL because backup and restore scripts do not exist.

- [ ] **Step 3: Implement private daily backups**

`backup_postgres.sh ENV_FILE` validates the environment, creates `BACKUP_DIR` with mode `700`, runs `pg_dump --format=custom --no-owner --no-acl` through the PostgreSQL container into a temporary file, renames only after success, applies mode `600`, and deletes regular backup files older than `BACKUP_RETENTION_DAYS`. Filenames use UTC: `smart_reminder-YYYYmmddTHHMMSSZ.dump`.

The script must never pass `POSTGRES_PASSWORD` on the command line or print the environment file.

- [ ] **Step 4: Implement explicit non-destructive restore**

`restore_postgres.sh ENV_FILE BACKUP_FILE` requires both arguments, confirms the file is a regular file inside the configured backup directory, prints the target database name, and requires the operator to type exactly `RESTORE`. It pipes the file to `pg_restore --exit-on-error --no-owner --no-acl --dbname "$POSTGRES_DB"` without `--clean` and without dropping the database. The runbook requires restoring into a separately named temporary database for routine drills.

- [ ] **Step 5: Verify Bash syntax and focused tests**

Run:

```bash
bash -n deploy/tencent/scripts/backup_postgres.sh
bash -n deploy/tencent/scripts/restore_postgres.sh
.venv/bin/pytest backend/tests/deployment/test_operations_scripts.py -q
```

Expected: both syntax checks exit `0`; all focused tests pass.

- [ ] **Step 6: Commit backup operations**

```bash
git add deploy/tencent/scripts/check_env.py deploy/tencent/scripts/backup_postgres.sh deploy/tencent/scripts/restore_postgres.sh backend/tests/deployment/test_operations_scripts.py
git commit -m "ops: add PostgreSQL backup and restore"
```

## Task 6: Write The Tencent Cloud Runbook

**Files:**
- Create: `deploy/tencent/README.md`
- Modify: `README.md`
- Modify: `Makefile`

- [ ] **Step 1: Add a failing documentation contract test**

Append to `backend/tests/deployment/test_operations_scripts.py`:

```python
def test_runbook_covers_security_release_backup_and_rollback():
    runbook = (REPO_ROOT / "deploy/tencent/README.md").read_text()
    for required in (
        "SSH 公钥",
        "Docker Compose v2.24.4",
        "bootstrap_tls.sh",
        "deploy.sh",
        "backup_postgres.sh",
        "restore_postgres.sh",
        "回滚",
        "22/80/443",
        "https://aipupu.cloud/api/v1/health",
    ):
        assert required in runbook
```

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/deployment/test_operations_scripts.py -q`

Expected: FAIL because the runbook does not exist.

- [ ] **Step 3: Write the exact operating procedure**

The runbook must include:

1. Tencent security-group rules: SSH from administrator IP only, public HTTP/HTTPS, no database or Redis ports.
2. Project-specific Ed25519 key generation and Tencent console public-key installation.
3. Verification of key login before disabling `PasswordAuthentication` and rotating the exposed initial password.
4. Ubuntu Docker Engine and Compose Plugin installation from Docker's official apt repository; verify Compose `>=2.24.4`.
5. Directory ownership for `/opt/smart-reminder/app`, `/opt/smart-reminder/shared`, and `/opt/smart-reminder/backups`.
6. Production environment creation from the example with mode `600`, using generated secrets and no shell metacharacters that require evaluation.
7. DNS A-record verification before TLS bootstrap.
8. Exact TLS bootstrap and release commands with full commit SHA.
9. Certificate renewal command and `nginx -t` before reload.
10. Daily backup cron/systemd timer, restore drill into a temporary database, disk monitoring, and 14-day retention.
11. Rollback by checking out the prior successful commit and rerunning `deploy.sh` with its full SHA; no database-volume rollback unless separately planned.
12. Health, logs, container status, certificate expiry, and common failure commands that do not print secrets.

- [ ] **Step 4: Link the runbook and add a local verification target**

Add to `README.md`:

```markdown
## 腾讯云预发布

`aipupu.cloud` 的单机预发布部署、HTTPS、备份与回滚步骤见 [`deploy/tencent/README.md`](deploy/tencent/README.md)。生产凭据只保存在服务器权限为 `600` 的环境文件中，不提交到 Git。
```

Add to `Makefile`:

```make
.PHONY: test-deployment

test-deployment:
	.venv/bin/pytest backend/tests/deployment -q
	bash -n deploy/tencent/scripts/bootstrap_tls.sh
	bash -n deploy/tencent/scripts/deploy.sh
	bash -n deploy/tencent/scripts/backup_postgres.sh
	bash -n deploy/tencent/scripts/restore_postgres.sh
```

- [ ] **Step 5: Verify the runbook contract**

Run: `make test-deployment`

Expected: all deployment tests pass and all shell scripts parse successfully.

- [ ] **Step 6: Commit the runbook**

```bash
git add deploy/tencent/README.md README.md Makefile backend/tests/deployment/test_operations_scripts.py
git commit -m "docs: add Tencent deployment runbook"
```

## Task 7: Run The Local Release Gate

**Files:**
- Modify only files required to fix failures introduced by Tasks 1-6.

- [ ] **Step 1: Install the updated development requirements**

Run: `.venv/bin/python -m pip install -r backend/requirements/dev.txt`

Expected: exits `0`.

- [ ] **Step 2: Run all backend and deployment tests**

Run: `.venv/bin/pytest backend/tests -q`

Expected: all tests pass, including existing reminder and notification API tests.

- [ ] **Step 3: Run Django checks and migration drift check**

```bash
.venv/bin/python backend/manage.py check
.venv/bin/python backend/manage.py makemigrations --check --dry-run
```

Expected: Django reports no issues and no model changes.

- [ ] **Step 4: Run deployment static checks**

```bash
make test-deployment
git diff --check
```

Expected: exit `0` with no whitespace errors.

- [ ] **Step 5: Record the unavailable local Docker check accurately**

Run: `docker compose version`.

If Docker remains unavailable on the Mac, record that Compose and Nginx runtime checks are pending server execution. Do not claim Docker validation passed. Do not install Docker Desktop without explicit user approval.

## Task 8: Configure Key Authentication And Deploy To Tencent Cloud

**Files:**
- No repository file changes unless server verification exposes a plan-owned bug.

- [ ] **Step 1: Generate a project-specific SSH key locally**

After user approval for writing under `~/.ssh`, run:

```bash
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/id_ed25519_smart_reminder -C smart-reminder-deploy
```

Use a passphrase entered interactively. Never place the private key, passphrase, or server password in commands, chat output, repository files, or logs.

- [ ] **Step 2: Install the public key through Tencent Cloud console**

Display only `~/.ssh/id_ed25519_smart_reminder.pub`. The user binds it to the server through the Tencent Cloud console and restarts the instance if required.

- [ ] **Step 3: Verify key-only login before changing SSH configuration**

Run:

```bash
ssh -i ~/.ssh/id_ed25519_smart_reminder -o IdentitiesOnly=yes -o BatchMode=yes ubuntu@aipupu.cloud true
```

Expected: exit `0` without a password prompt. Only then disable password authentication and rotate the initial password.

- [ ] **Step 4: Initialize the host and checkout the deployment branch**

Follow `deploy/tencent/README.md` exactly. Confirm Ubuntu version, free disk, memory, security-group exposure, Docker/Compose versions, repository ownership, and environment-file permissions before deployment.

- [ ] **Step 5: Verify DNS and issue TLS**

Confirm the public A record equals the target server. Run `bootstrap_tls.sh` only after DNS resolves. Verify the resulting certificate names include `aipupu.cloud`.

- [ ] **Step 6: Deploy the exact reviewed commit**

Run `deploy.sh` with the full commit SHA and server environment path. Do not deploy an uncommitted worktree or a moving branch name.

- [ ] **Step 7: Run the server release gate**

```bash
docker compose --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml -f deploy/tencent/compose.production.yaml config --quiet
docker compose --env-file /opt/smart-reminder/shared/.env.production \
  -f compose.yaml -f deploy/tencent/compose.production.yaml \
  --profile production exec -T nginx nginx -t
curl --fail --show-error --silent https://aipupu.cloud/api/v1/health
```

Expected: Compose and Nginx checks exit `0`; the public health endpoint returns `{"status":"ok","service":"smart-reminder-api"}`.

- [ ] **Step 8: Verify restart, backup, and iPhone access**

Restart the server once, verify all production services recover, create a database backup, restore it into a temporary database, and configure the iPhone build with `API_BASE_URL=https://aipupu.cloud`. Confirm a text reminder draft and confirmation complete over HTTPS.

## Final Verification Checklist

- [ ] No OCR or medicine files changed on this branch.
- [ ] No real server password, SSH private key, API key, Token, or production `.env` is tracked.
- [ ] PostgreSQL, Redis, MinIO, and Django port `8000` are not publicly published by the production overlay.
- [ ] Plain HTTP serves only ACME bootstrap or redirects to HTTPS.
- [ ] Releases require a clean exact Git revision and stop on migration or health failure.
- [ ] Backups are private, retained for 14 days, and restoration is explicit.
- [ ] Local tests are green; unavailable Docker checks are stated as pending.
- [ ] Server Compose, Nginx, HTTPS, restart, backup, restore, and iPhone checks are complete before calling the deployment finished.

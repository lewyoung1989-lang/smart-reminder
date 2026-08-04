import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = REPO_ROOT / "deploy/tencent/scripts"


def test_release_scripts_are_valid_bash():
    for name in ("bootstrap_tls.sh", "configure_secrets.sh", "deploy.sh"):
        result = subprocess.run(
            ["bash", "-n", str(SCRIPTS / name)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr


def test_secret_configurator_does_not_echo_or_source_production_values():
    script = (SCRIPTS / "configure_secrets.sh").read_text()
    assert "read -r -s" in script
    assert "mktemp" in script
    assert "chmod 600" in script
    assert "check_env.py" in script
    assert 'source "$ENV_FILE"' not in script
    assert "set -x" not in script
    assert 'echo "$DEEPSEEK_API_KEY"' not in script


def test_minio_initializer_uses_shell_matching_for_lifecycle_rules():
    script = (SCRIPTS / "init_minio.sh").read_text()
    assert "grep" not in script
    assert "existing_rules=$(mc ilm rule ls --json" in script
    assert "case \"$existing_rules\" in" in script


def test_deploy_requires_clean_expected_revision_and_health_check():
    script = (SCRIPTS / "deploy.sh").read_text()
    assert "git diff --quiet" in script
    assert "git diff --cached --quiet" in script
    assert "git status --porcelain" in script
    assert "EXPECTED_SHA" in script
    assert "manage.py migrate --noinput" in script
    assert "/api/v1/health" in script
    assert "'Host':'aipupu.cloud'" in script
    assert "--profile production" in script


def test_deploy_initializes_minio_and_smoke_checks_ocr_before_start():
    script = (SCRIPTS / "deploy.sh").read_text()
    build = script.index('build api ocr-worker')
    minio = script.index('up -d postgres redis minio')
    initialize = script.index('run --rm minio-init')
    migrate = script.index('manage.py migrate --noinput')
    smoke = script.index('manage.py check_ocr')
    start = script.index('up -d api worker ocr-worker beat')
    assert build < minio < initialize < migrate < smoke < start


def test_tls_bootstrap_uses_webroot_and_never_starts_plain_http_api():
    script = (SCRIPTS / "bootstrap_tls.sh").read_text()
    assert "certonly" in script
    assert "--webroot" in script
    assert "nginx-bootstrap" in script
    assert "up -d api" not in script
    assert 'source "$ENV_FILE"' not in script


def test_tls_bootstrap_requests_both_domains():
    script = (SCRIPTS / "bootstrap_tls.sh").read_text()
    assert (
        'FILES_DOMAIN=$(python3 "$VALIDATOR" "$ENV_FILE" --get FILES_DOMAIN)'
        in script
    )
    assert '--domain "$DOMAIN"' in script
    assert '--domain "$FILES_DOMAIN"' in script


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
        "files.aipupu.cloud",
        "S3_INTERNAL_ENDPOINT",
        "S3_PUBLIC_ENDPOINT",
        "configure_secrets.sh",
        "MinIO Console",
        "24 小时",
        "check_ocr",
    ):
        assert required in runbook

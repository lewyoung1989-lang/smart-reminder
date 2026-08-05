import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = REPO_ROOT / "deploy/tencent/scripts"
SYSTEMD = REPO_ROOT / "deploy/tencent/systemd"


def test_release_scripts_are_valid_bash():
    for name in (
        "bootstrap_tls.sh",
        "configure_secrets.sh",
        "deploy.sh",
        "install_logging.sh",
        "logs.sh",
        "operation_logging.sh",
        "renew_certificate.sh",
        "verify_logging.sh",
    ):
        result = subprocess.run(
            ["bash", "-n", str(SCRIPTS / name)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr


def test_journald_and_logrotate_keep_logs_for_seven_days():
    journald = (
        REPO_ROOT / "deploy/tencent/logging/50-smart-reminder.conf"
    ).read_text()
    assert "Storage=persistent" in journald
    assert "Compress=yes" in journald
    assert "MaxRetentionSec=7day" in journald
    assert "SystemMaxUse=1G" in journald

    rotate = (
        REPO_ROOT / "deploy/tencent/logging/smart-reminder.logrotate"
    ).read_text()
    for path in (
        "/opt/smart-reminder/logs/deploy/deploy.log",
        "/opt/smart-reminder/logs/backup/backup.log",
        "/opt/smart-reminder/logs/cert/cert.log",
    ):
        assert path in rotate
    assert "/opt/smart-reminder/logs/*/*.log" not in rotate
    assert "daily" in rotate
    assert "rotate 7" in rotate
    assert "maxage 7" in rotate
    assert "create 0640 ubuntu ubuntu" in rotate


def test_logging_installer_uses_expected_paths_and_permissions():
    script = (SCRIPTS / "install_logging.sh").read_text()
    for path in ("logs/deploy", "logs/backup", "logs/cert"):
        assert path in script
    assert "0750" in script
    assert "ubuntu" in script
    assert "systemd-journald" in script
    assert "50-smart-reminder.conf" in script
    assert "smart-reminder.logrotate" in script
    assert "verify_logging.sh" in script


def test_log_query_rejects_unknown_service_and_uses_stable_tag(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    capture = tmp_path / "journalctl.args"
    journalctl = fake_bin / "journalctl"
    journalctl.write_text(
        "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" >\"$CAPTURE_FILE\"\n"
    )
    journalctl.chmod(0o755)
    env = os.environ.copy()
    env.update(PATH=f"{fake_bin}:{env['PATH']}", CAPTURE_FILE=str(capture))

    rejected = subprocess.run(
        ["bash", str(SCRIPTS / "logs.sh"), "unknown"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert rejected.returncode != 0
    assert not capture.exists()

    accepted = subprocess.run(
        [
            "bash",
            str(SCRIPTS / "logs.sh"),
            "api",
            "--since",
            "2 hours ago",
            "--level",
            "error",
            "--follow",
        ],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert accepted.returncode == 0, accepted.stderr
    arguments = capture.read_text().splitlines()
    assert "CONTAINER_TAG=smart-reminder/api" in arguments
    assert "--since" in arguments
    assert "2 hours ago" in arguments
    assert "--grep" in arguments
    assert any("ERROR" in argument and "CRITICAL" in argument for argument in arguments)
    assert "--case-sensitive=no" in arguments
    assert "--priority" not in arguments
    assert "--follow" in arguments
    assert "--output=short-iso-precise" in arguments


def test_logging_verifier_rejects_later_journald_override(tmp_path):
    assert "export LC_ALL=C" in (SCRIPTS / "verify_logging.sh").read_text()

    system_root = tmp_path / "system"
    journal_dropins = system_root / "etc/systemd/journald.conf.d"
    journal_dropins.mkdir(parents=True)
    (system_root / "var/log/journal").mkdir(parents=True)
    (journal_dropins / "50-smart-reminder.conf").write_text(
        "[Journal]\nStorage=persistent\nCompress=yes\n"
        "MaxRetentionSec=7day\nSystemMaxUse=1G\n"
    )
    log_root = tmp_path / "logs"
    for category in ("deploy", "backup", "cert"):
        (log_root / category).mkdir(parents=True)

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    systemctl = fake_bin / "systemctl"
    systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
    systemctl.chmod(0o755)
    docker = fake_bin / "docker"
    docker.write_text(
        "#!/usr/bin/env bash\nprintf '%s\\n' "
        "'[\"json-file\",\"journald\"]'\n"
    )
    docker.chmod(0o755)
    env = os.environ.copy()
    env.update(
        PATH=f"{fake_bin}:{env['PATH']}",
        SMART_REMINDER_SYSTEM_ROOT=str(system_root),
        SMART_REMINDER_LOG_ROOT=str(log_root),
    )

    accepted = subprocess.run(
        ["bash", str(SCRIPTS / "verify_logging.sh")],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert accepted.returncode == 0, accepted.stderr

    (journal_dropins / "60-override.conf").write_text(
        "[Journal]\nSystemMaxUse=10G\n"
    )
    rejected = subprocess.run(
        ["bash", str(SCRIPTS / "verify_logging.sh")],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert rejected.returncode != 0
    assert "60-override.conf" in rejected.stderr


def test_operation_logger_creates_private_daily_log_and_rejects_bad_directory(
    tmp_path,
):
    log_root = tmp_path / "logs"
    (log_root / "backup").mkdir(parents=True)
    env = os.environ.copy()
    env["SMART_REMINDER_LOG_ROOT"] = str(log_root)
    command = (
        'set -Eeuo pipefail; source "$1"; start_operation_log backup; '
        "printf '%s\\n' operation-test"
    )

    accepted = subprocess.run(
        ["bash", "-c", command, "operation-test", SCRIPTS / "operation_logging.sh"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert accepted.returncode == 0, accepted.stderr
    log_file = log_root / "backup/backup.log"
    assert log_file.stat().st_mode & 0o777 == 0o640
    assert "operation-test" in log_file.read_text()

    env["SMART_REMINDER_LOG_ROOT"] = str(tmp_path / "missing")
    rejected = subprocess.run(
        ["bash", "-c", command, "operation-test", SCRIPTS / "operation_logging.sh"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert rejected.returncode != 0


def test_operational_scripts_use_their_stable_log_categories():
    expected = {
        "deploy.sh": "deploy",
        "backup_postgres.sh": "backup",
        "renew_certificate.sh": "cert",
    }
    for name, category in expected.items():
        script = (SCRIPTS / name).read_text()
        assert "operation_logging.sh" in script
        assert f"start_operation_log {category}" in script
        assert "set -x" not in script

    helper = (SCRIPTS / "operation_logging.sh").read_text()
    assert "umask 027" in helper
    assert "tee -a" in helper
    assert "chmod 0640" in helper
    assert "SMART_REMINDER_LOG_ROOT" in helper


def test_systemd_units_call_repo_scripts_without_reading_secret_values():
    backup_service = (
        SYSTEMD / "smart-reminder-postgres-backup.service"
    ).read_text()
    backup_timer = (SYSTEMD / "smart-reminder-postgres-backup.timer").read_text()
    cert_service = (SYSTEMD / "smart-reminder-cert-renew.service").read_text()
    cert_timer = (SYSTEMD / "smart-reminder-cert-renew.timer").read_text()

    assert "User=ubuntu" in backup_service
    assert "/opt/smart-reminder/app/deploy/tencent/scripts/backup_postgres.sh" in (
        backup_service
    )
    assert "/opt/smart-reminder/app/deploy/tencent/scripts/renew_certificate.sh" in (
        cert_service
    )
    assert "EnvironmentFile=" not in backup_service + cert_service
    assert "OnCalendar=*-*-* 03:00:00" in backup_timer
    assert "OnCalendar=monthly" in cert_timer
    assert "Persistent=true" in backup_timer + cert_timer

    installer = (SCRIPTS / "install_logging.sh").read_text()
    assert "smart-reminder-postgres-backup.timer" in installer
    assert "smart-reminder-cert-renew.timer" in installer
    assert "systemctl daemon-reload" in installer
    assert "systemctl enable --now" in installer


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
    assert script.index("verify_logging.sh") < script.index('build api ocr-worker')


def test_deploy_initializes_minio_and_smoke_checks_ocr_before_start():
    script = (SCRIPTS / "deploy.sh").read_text()
    build = script.index('build api ocr-worker')
    minio = script.index('up -d postgres redis minio')
    initialize = script.index('run --rm minio-init')
    migrate = script.index('manage.py migrate --noinput')
    smoke = script.index('manage.py check_ocr')
    start = script.index('up -d api worker ocr-worker beat')
    assert build < minio < initialize < migrate < smoke < start


def test_deploy_validates_and_reloads_nginx_after_api_replacement():
    script = (SCRIPTS / "deploy.sh").read_text()
    start_nginx = script.index("--profile production up -d nginx")
    validate_nginx = script.index("exec -T nginx nginx -t")
    reload_nginx = script.index("exec -T nginx nginx -s reload")
    assert start_nginx < validate_nginx < reload_nginx


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
        "/var/log/journal/",
        "/opt/smart-reminder/logs/deploy/",
        "/opt/smart-reminder/logs/backup/",
        "/opt/smart-reminder/logs/cert/",
        "install_logging.sh",
        "logs.sh api",
        "journalctl --disk-usage",
        "保留 7 天",
    ):
        assert required in runbook

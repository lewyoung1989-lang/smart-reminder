import re
import subprocess
import sys
from pathlib import Path

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
EXAMPLE = REPO_ROOT / "deploy/tencent/env.production.example"
VALIDATOR = REPO_ROOT / "deploy/tencent/scripts/check_env.py"


class ComposeLoader(yaml.SafeLoader):
    pass


ComposeLoader.add_constructor("!reset", lambda loader, node: [])


def parse_example_values():
    values = {}
    for raw_line in EXAMPLE.read_text().splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    return values


def valid_example_values():
    values = parse_example_values()
    values.update(
        DJANGO_SECRET_KEY="test-django-secret",
        POSTGRES_PASSWORD="test-postgres-secret",
        DEEPSEEK_API_KEY="test-deepseek-key",
        CERTBOT_EMAIL="owner@example.com",
        S3_ACCESS_KEY_ID="test-app-user",
        S3_SECRET_ACCESS_KEY="test-app-secret",
        MINIO_ROOT_USER="test-root-user",
        MINIO_ROOT_PASSWORD="test-root-secret",
    )
    return values


def run_validator(tmp_path, values, *extra_args):
    env_file = tmp_path / "production.env"
    env_file.write_text(
        "".join(f"{key}={value}\n" for key, value in values.items())
    )
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(env_file), *extra_args],
        capture_output=True,
        text=True,
        check=False,
    )


def test_example_lists_required_production_variables_without_secrets():
    values = parse_example_values()

    assert values["DOMAIN"] == "aipupu.cloud"
    assert values["DJANGO_DEBUG"] == "false"
    assert values["DJANGO_ALLOWED_HOSTS"] == "aipupu.cloud"
    assert values["DJANGO_CSRF_TRUSTED_ORIGINS"] == "https://aipupu.cloud"
    assert values["LOG_LEVEL"] == "INFO"
    assert values["OCR_SEMANTIC_PROVIDER"] == "deepseek"
    assert values["OCR_SEMANTIC_TIMEOUT_SECONDS"] == "8"
    assert values["OCR_DEBUG_TEXT_LOGGING"] == "false"
    assert values["OCR_ENABLED"] == "false"
    for secret in (
        "DJANGO_SECRET_KEY",
        "POSTGRES_PASSWORD",
        "DEEPSEEK_API_KEY",
        "CERTBOT_EMAIL",
    ):
        assert values[secret] == ""


def test_example_has_private_minio_and_dual_endpoint_contract():
    values = parse_example_values()
    assert values["FILES_DOMAIN"] == "files.aipupu.cloud"
    assert values["S3_INTERNAL_ENDPOINT"] == "http://minio:9000"
    assert values["S3_PUBLIC_ENDPOINT"] == "https://files.aipupu.cloud"
    assert values["S3_BUCKET"] == "smart-reminder-private"
    assert values["S3_ADDRESSING_STYLE"] == "path"
    for secret in (
        "S3_ACCESS_KEY_ID",
        "S3_SECRET_ACCESS_KEY",
        "MINIO_ROOT_USER",
        "MINIO_ROOT_PASSWORD",
    ):
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


def test_validator_rejects_invalid_minio_boundary(tmp_path):
    values = valid_example_values()
    values["S3_PUBLIC_ENDPOINT"] = "http://files.aipupu.cloud"
    values["S3_INTERNAL_ENDPOINT"] = "https://files.aipupu.cloud"
    values["S3_ADDRESSING_STYLE"] = "virtual"
    values["MINIO_ROOT_USER"] = values["S3_ACCESS_KEY_ID"]

    result = run_validator(tmp_path, values)

    assert result.returncode == 1
    assert "S3_PUBLIC_ENDPOINT" in result.stderr
    assert "S3_INTERNAL_ENDPOINT" in result.stderr
    assert "S3_ADDRESSING_STYLE" in result.stderr
    assert "MINIO_ROOT_USER" in result.stderr


def test_validator_reads_a_value_without_shell_evaluation(tmp_path):
    result = run_validator(
        tmp_path,
        valid_example_values(),
        "--get",
        "DOMAIN",
    )

    assert result.returncode == 0
    assert result.stdout.strip() == "aipupu.cloud"


def test_validator_rejects_invalid_ocr_debug_flag(tmp_path):
    values = valid_example_values()
    values["OCR_DEBUG_TEXT_LOGGING"] = "yes"

    result = run_validator(tmp_path, values)

    assert result.returncode == 1
    assert "OCR_DEBUG_TEXT_LOGGING" in result.stderr


def test_validator_rejects_unknown_ocr_semantic_provider(tmp_path):
    values = valid_example_values()
    values["OCR_SEMANTIC_PROVIDER"] = "unknown"

    result = run_validator(tmp_path, values)

    assert result.returncode == 1
    assert "OCR_SEMANTIC_PROVIDER" in result.stderr


def test_validator_rejects_invalid_ocr_semantic_timeout(tmp_path):
    values = valid_example_values()
    values["OCR_SEMANTIC_TIMEOUT_SECONDS"] = "zero"

    result = run_validator(tmp_path, values)

    assert result.returncode == 1
    assert "OCR_SEMANTIC_TIMEOUT_SECONDS" in result.stderr


def test_example_has_complete_non_secret_asr_contract():
    values = parse_example_values()
    assert {key: values[key] for key in (
        "ASR_PROVIDER",
        "ASR_BASE_URL",
        "ASR_MODEL",
        "ASR_TIMEOUT_SECONDS",
        "ASR_MAX_AUDIO_BYTES",
        "ASR_MAX_REQUEST_BYTES",
        "ASR_MIN_DURATION_SECONDS",
        "ASR_MAX_DURATION_SECONDS",
        "ASR_GLOBAL_CONCURRENCY",
        "ASR_CONCURRENCY_PER_USER",
        "ASR_LEASE_TTL_SECONDS",
        "ASR_USER_RATE",
        "ASR_IP_RATE",
        "ASR_REDIS_URL",
        "ASR_THROTTLE_REDIS_URL",
        "ASR_TRUSTED_PROXY_IPS",
    )} == {
        "ASR_PROVIDER": "funasr",
        "ASR_BASE_URL": "http://funasr:8000",
        "ASR_MODEL": "paraformer-zh",
        "ASR_TIMEOUT_SECONDS": "20",
        "ASR_MAX_AUDIO_BYTES": "4194304",
        "ASR_MAX_REQUEST_BYTES": "5242880",
        "ASR_MIN_DURATION_SECONDS": "0.3",
        "ASR_MAX_DURATION_SECONDS": "20",
        "ASR_GLOBAL_CONCURRENCY": "1",
        "ASR_CONCURRENCY_PER_USER": "1",
        "ASR_LEASE_TTL_SECONDS": "25",
        "ASR_USER_RATE": "10/min",
        "ASR_IP_RATE": "30/min",
        "ASR_REDIS_URL": "redis://redis:6379/0",
        "ASR_THROTTLE_REDIS_URL": "redis://redis:6379/2",
        "ASR_TRUSTED_PROXY_IPS": "172.29.0.10",
    }


@pytest.mark.parametrize(
    ("key", "value", "message"),
    (
        ("ASR_BASE_URL", "https://asr.example.com", "ASR_BASE_URL"),
        ("ASR_REDIS_URL", "redis://example.com:6379/0", "ASR_REDIS_URL"),
        (
            "ASR_THROTTLE_REDIS_URL",
            "redis://redis:6379/0",
            "ASR_THROTTLE_REDIS_URL",
        ),
        ("ASR_TIMEOUT_SECONDS", "0", "ASR_TIMEOUT_SECONDS"),
        ("ASR_MAX_AUDIO_BYTES", "0", "ASR_MAX_AUDIO_BYTES"),
        ("ASR_MAX_REQUEST_BYTES", "4194304", "ASR_MAX_REQUEST_BYTES"),
        ("ASR_MIN_DURATION_SECONDS", "0", "ASR_MIN_DURATION_SECONDS"),
        ("ASR_MAX_DURATION_SECONDS", "0.2", "ASR_MAX_DURATION_SECONDS"),
        ("ASR_GLOBAL_CONCURRENCY", "2", "ASR_GLOBAL_CONCURRENCY"),
        ("ASR_CONCURRENCY_PER_USER", "2", "ASR_CONCURRENCY_PER_USER"),
        ("ASR_LEASE_TTL_SECONDS", "20", "ASR_LEASE_TTL_SECONDS"),
        ("ASR_USER_RATE", "unlimited", "ASR_USER_RATE"),
        ("ASR_IP_RATE", "0/min", "ASR_IP_RATE"),
        (
            "ASR_TRUSTED_PROXY_IPS",
            "172.29.0.10,172.29.0.11",
            "ASR_TRUSTED_PROXY_IPS",
        ),
        ("OCR_ENABLED", "yes", "OCR_ENABLED"),
    ),
)
def test_validator_rejects_invalid_asr_and_ocr_boundaries(
    tmp_path, key, value, message
):
    values = valid_example_values()
    values[key] = value

    result = run_validator(tmp_path, values)

    assert result.returncode == 1
    assert message in result.stderr


def test_validator_allows_ocr_secrets_to_be_blank_when_disabled(tmp_path):
    values = valid_example_values()
    values.update(
        OCR_ENABLED="false",
        S3_ACCESS_KEY_ID="",
        S3_SECRET_ACCESS_KEY="",
        MINIO_ROOT_USER="",
        MINIO_ROOT_PASSWORD="",
    )

    result = run_validator(tmp_path, values)

    assert result.returncode == 0, result.stderr


def test_validator_requires_ocr_secrets_when_enabled(tmp_path):
    values = valid_example_values()
    values.update(
        OCR_ENABLED="true",
        S3_ACCESS_KEY_ID="",
        S3_SECRET_ACCESS_KEY="",
        MINIO_ROOT_USER="",
        MINIO_ROOT_PASSWORD="",
    )

    result = run_validator(tmp_path, values)

    assert result.returncode == 1
    assert "S3_ACCESS_KEY_ID" in result.stderr
    assert "MINIO_ROOT_PASSWORD" in result.stderr


def test_validator_caps_asr_timeout_below_outer_proxy_timeouts(tmp_path):
    compose = yaml.load(
        (REPO_ROOT / "deploy/tencent/compose.production.yaml").read_text(),
        Loader=ComposeLoader,
    )
    gunicorn_command = compose["services"]["api"]["command"]
    gunicorn_timeout = int(
        re.search(r"--timeout\s+(\d+)", gunicorn_command).group(1)
    )
    nginx_config = (
        REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf"
    ).read_text()
    api_server = nginx_config.split("server_name aipupu.cloud;", 1)[1]
    nginx_timeout = int(
        re.search(r"proxy_read_timeout\s+(\d+)s;", api_server).group(1)
    )

    accepted = valid_example_values()
    accepted["ASR_TIMEOUT_SECONDS"] = "25"
    accepted["ASR_LEASE_TTL_SECONDS"] = "26"
    rejected = dict(accepted)
    rejected["ASR_TIMEOUT_SECONDS"] = "25.1"

    accepted_result = run_validator(tmp_path, accepted)
    rejected_result = run_validator(tmp_path, rejected)

    assert accepted_result.returncode == 0, accepted_result.stderr
    assert rejected_result.returncode == 1
    assert "ASR_TIMEOUT_SECONDS" in rejected_result.stderr
    asr_timeout = float(accepted["ASR_TIMEOUT_SECONDS"])
    assert asr_timeout <= 25 < gunicorn_timeout < nginx_timeout

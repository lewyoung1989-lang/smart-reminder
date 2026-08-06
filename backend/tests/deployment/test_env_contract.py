import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
EXAMPLE = REPO_ROOT / "deploy/tencent/env.production.example"
VALIDATOR = REPO_ROOT / "deploy/tencent/scripts/check_env.py"


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
        JWT_SIGNING_KEY="test-jwt-signing-secret-at-least-32-bytes",
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
    assert values["AUTH_CACHE_URL"] == "redis://redis:6379/4"
    for secret in (
        "DJANGO_SECRET_KEY",
        "JWT_SIGNING_KEY",
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
    assert "JWT_SIGNING_KEY" in result.stderr
    assert "POSTGRES_PASSWORD" in result.stderr
    assert "DEEPSEEK_API_KEY" in result.stderr
    assert "CERTBOT_EMAIL" in result.stderr


def test_readme_does_not_compile_a_shared_token_into_the_app():
    readme = (REPO_ROOT / "README.md").read_text()

    assert "--dart-define=API_ACCESS_TOKEN" not in readme


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

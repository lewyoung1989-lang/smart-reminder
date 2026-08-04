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
    for secret in (
        "DJANGO_SECRET_KEY",
        "POSTGRES_PASSWORD",
        "DEEPSEEK_API_KEY",
        "CERTBOT_EMAIL",
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

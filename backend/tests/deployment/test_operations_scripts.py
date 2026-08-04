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
    assert "git status --porcelain" in script
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
    assert 'source "$ENV_FILE"' not in script

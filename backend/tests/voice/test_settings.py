import json
import os
from pathlib import Path
import subprocess
import sys

from django.conf import settings


def test_asr_defaults_are_safe_for_v1():
    assert settings.ASR_PROVIDER == "funasr"
    assert settings.ASR_BASE_URL == "http://localhost:18001"
    assert settings.ASR_MODEL == "paraformer-zh"
    assert settings.ASR_MAX_AUDIO_BYTES == 4 * 1024 * 1024
    assert settings.ASR_MAX_REQUEST_BYTES == 5 * 1024 * 1024
    assert settings.ASR_MIN_DURATION_SECONDS == 0.3
    assert settings.ASR_MAX_DURATION_SECONDS == 20
    assert settings.ASR_GLOBAL_CONCURRENCY == 1
    assert settings.ASR_CONCURRENCY_PER_USER == 1
    assert settings.ASR_LEASE_TTL_SECONDS > settings.ASR_TIMEOUT_SECONDS
    assert settings.ASR_USER_RATE == "10/min"
    assert settings.ASR_IP_RATE == "30/min"


def test_configures_shared_redis_cache_when_throttle_url_is_set():
    environment = os.environ.copy()
    environment["ASR_THROTTLE_REDIS_URL"] = "redis://redis:6379/2"
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            (
                "import json; from config.settings import CACHES; "
                "print(json.dumps(CACHES['default']))"
            ),
        ],
        cwd=Path(settings.BASE_DIR),
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )
    cache_config = json.loads(result.stdout)

    assert cache_config["BACKEND"] == "django.core.cache.backends.redis.RedisCache"
    assert cache_config["LOCATION"] == "redis://redis:6379/2"
    assert cache_config["KEY_PREFIX"] == "smart-reminder-asr-throttle"


def test_rejects_unsupported_v1_concurrency_configuration():
    environment = os.environ.copy()
    environment["ASR_GLOBAL_CONCURRENCY"] = "2"
    result = subprocess.run(
        [sys.executable, "-c", "import config.settings"],
        cwd=Path(settings.BASE_DIR),
        env=environment,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert "V1 only supports ASR concurrency of 1" in result.stderr

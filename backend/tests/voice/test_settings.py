import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlparse

from django.conf import settings


def test_asr_defaults_are_safe_for_v1():
    assert settings.ASR_PROVIDER == "funasr"
    asr_url = urlparse(settings.ASR_BASE_URL)
    assert asr_url.scheme == "http"
    assert asr_url.hostname in {"localhost", "127.0.0.1"}
    assert asr_url.port == 18001
    assert settings.ASR_MODEL == "paraformer-zh"
    assert settings.ASR_MAX_AUDIO_BYTES == 4 * 1024 * 1024
    assert settings.ASR_MAX_REQUEST_BYTES == 5 * 1024 * 1024
    assert settings.ASR_MIN_DURATION_SECONDS == 0.3
    assert settings.ASR_MAX_DURATION_SECONDS == 60
    assert settings.ASR_GLOBAL_CONCURRENCY == 1
    assert settings.ASR_CONCURRENCY_PER_USER == 1
    assert settings.ASR_LEASE_TTL_SECONDS > settings.ASR_TIMEOUT_SECONDS
    assert settings.ASR_USER_RATE == "10/min"
    assert settings.ASR_IP_RATE == "30/min"


def test_configures_isolated_auth_and_asr_throttle_caches():
    environment = os.environ.copy()
    environment["AUTH_CACHE_URL"] = "redis://redis:6379/4"
    environment["ASR_THROTTLE_REDIS_URL"] = "redis://redis:6379/2"
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            (
                "import json; from config.settings import CACHES; "
                "print(json.dumps(CACHES))"
            ),
        ],
        cwd=Path(settings.BASE_DIR),
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )
    caches_config = json.loads(result.stdout)

    assert caches_config["auth"]["LOCATION"] == "redis://redis:6379/4"
    assert caches_config["asr_throttle"]["LOCATION"] == "redis://redis:6379/2"
    assert caches_config["asr_throttle"]["KEY_PREFIX"] == "smart-reminder-asr-throttle"


def test_voice_throttles_use_the_dedicated_asr_cache_alias():
    environment = os.environ.copy()
    environment["ASR_THROTTLE_REDIS_URL"] = "redis://redis:6379/2"
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            (
                "from django.core.cache import caches; "
                "from apps.voice.api.throttles import VoiceTranscriptionIpThrottle, "
                "VoiceTranscriptionUserThrottle; "
                "assert VoiceTranscriptionIpThrottle.cache is caches['asr_throttle']; "
                "assert VoiceTranscriptionUserThrottle.cache is caches['asr_throttle']"
            ),
        ],
        cwd=Path(settings.BASE_DIR),
        env=environment,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr


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


def test_rejects_memory_lease_provider_outside_debug():
    environment = os.environ.copy()
    environment["DJANGO_DEBUG"] = "false"
    environment["ASR_LEASE_PROVIDER"] = "memory"
    result = subprocess.run(
        [sys.executable, "-c", "import config.settings"],
        cwd=Path(settings.BASE_DIR),
        env=environment,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert "ASR memory leases are only allowed when DEBUG=True" in result.stderr

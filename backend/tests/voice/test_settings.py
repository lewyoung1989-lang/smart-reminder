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

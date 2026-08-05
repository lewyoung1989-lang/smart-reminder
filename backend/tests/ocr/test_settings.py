from django.conf import settings


def test_ocr_defaults_are_safe_for_cpu_worker():
    assert settings.OCR_PROVIDER == "rapidocr"
    assert settings.OCR_LANGUAGE == "ch"
    assert settings.OCR_TEXT_SCORE == 0.50
    assert settings.OCR_MAX_IMAGE_BYTES == 8 * 1024 * 1024
    assert settings.OCR_MAX_IMAGE_SIDE == 2048
    assert settings.OCR_JOB_RETENTION_HOURS == 24
    assert settings.OCR_TASK_SOFT_TIME_LIMIT == 45
    assert settings.OCR_TASK_TIME_LIMIT == 60
    assert settings.OCR_MAX_RETRIES == 2
    assert settings.OCR_DEBUG_TEXT_LOGGING is False


def test_s3_endpoints_have_explicit_internal_and_public_settings():
    assert settings.S3_INTERNAL_ENDPOINT
    assert settings.S3_PUBLIC_ENDPOINT

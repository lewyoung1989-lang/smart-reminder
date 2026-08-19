#!/usr/bin/env python3
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


REQUIRED = {
    "DOMAIN",
    "FILES_DOMAIN",
    "SITE_OWNER_NAME",
    "SITE_CONTACT_EMAIL",
    "ICP_FILING_NUMBER",
    "DJANGO_SECRET_KEY",
    "JWT_SIGNING_KEY",
    "DJANGO_DEBUG",
    "DJANGO_ALLOWED_HOSTS",
    "DJANGO_CSRF_TRUSTED_ORIGINS",
    "POSTGRES_DB",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "CELERY_BROKER_URL",
    "CELERY_RESULT_BACKEND",
    "AUTH_CACHE_URL",
    "DEEPSEEK_API_KEY",
    "ASR_PROVIDER",
    "ASR_BASE_URL",
    "ASR_LEASE_PROVIDER",
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
    "OCR_ENABLED",
    "OCR_PROVIDER",
    "OCR_STORAGE_PROVIDER",
    "OCR_JOB_RETENTION_HOURS",
    "OCR_QUEUE",
    "S3_INTERNAL_ENDPOINT",
    "S3_PUBLIC_ENDPOINT",
    "S3_BUCKET",
    "S3_REGION",
    "S3_ADDRESSING_STYLE",
    "CERTBOT_EMAIL",
    "BACKUP_DIR",
    "BACKUP_RETENTION_DAYS",
}

OCR_SECRETS = {
    "S3_ACCESS_KEY_ID",
    "S3_SECRET_ACCESS_KEY",
    "MINIO_ROOT_USER",
    "MINIO_ROOT_PASSWORD",
}

RATE_PATTERN = re.compile(r"^[1-9][0-9]*/(sec|min|hour|day)$")


def parse_env(path: Path) -> dict[str, str]:
    values = {}
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"line {line_number} must use KEY=VALUE")
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def validate(values: dict[str, str]) -> list[str]:
    errors = [
        f"{key} is required" for key in sorted(REQUIRED) if not values.get(key)
    ]
    ocr_enabled = values.get("OCR_ENABLED")
    if ocr_enabled not in {None, "", "true", "false"}:
        errors.append("OCR_ENABLED must be true or false")
    if ocr_enabled == "true":
        errors.extend(
            f"{key} is required"
            for key in sorted(OCR_SECRETS)
            if not values.get(key)
        )
    if values.get("DOMAIN") not in {None, "", "aipupu.cloud"}:
        errors.append("DOMAIN must be aipupu.cloud")
    contact_email = values.get("SITE_CONTACT_EMAIL", "")
    if contact_email and not re.fullmatch(
        r"[^@\s]+@[^@\s]+\.[^@\s]+", contact_email
    ):
        errors.append("SITE_CONTACT_EMAIL must be a valid email address")
    icp_number = values.get("ICP_FILING_NUMBER", "")
    if icp_number and not re.fullmatch(
        r"[\u4e00-\u9fff]ICP\u5907\d+\u53f7(?:-\d+)?", icp_number
    ):
        errors.append("ICP_FILING_NUMBER must be a valid ICP filing number")
    security_number = values.get("PUBLIC_SECURITY_FILING_NUMBER", "")
    security_code = values.get("PUBLIC_SECURITY_RECORD_CODE", "")
    if bool(security_number) != bool(security_code):
        errors.append(
            "PUBLIC_SECURITY_FILING_NUMBER and "
            "PUBLIC_SECURITY_RECORD_CODE must be configured together"
        )
    if security_code and not re.fullmatch(r"\d{14,20}", security_code):
        errors.append("PUBLIC_SECURITY_RECORD_CODE must contain 14-20 digits")
    files_domain = values.get("FILES_DOMAIN")
    if files_domain not in {None, "", "files.aipupu.cloud"}:
        errors.append("FILES_DOMAIN must be files.aipupu.cloud")
    public_endpoint = urlparse(values.get("S3_PUBLIC_ENDPOINT", ""))
    if (
        public_endpoint.scheme != "https"
        or public_endpoint.hostname != files_domain
    ):
        errors.append("S3_PUBLIC_ENDPOINT must use HTTPS FILES_DOMAIN")
    if values.get("S3_INTERNAL_ENDPOINT") not in {
        None,
        "",
        "http://minio:9000",
    }:
        errors.append("S3_INTERNAL_ENDPOINT must be http://minio:9000")
    if values.get("S3_ADDRESSING_STYLE") not in {None, "", "path"}:
        errors.append("S3_ADDRESSING_STYLE must be path")
    if (
        values.get("MINIO_ROOT_USER")
        and values.get("MINIO_ROOT_USER") == values.get("S3_ACCESS_KEY_ID")
    ):
        errors.append("MINIO_ROOT_USER must differ from S3_ACCESS_KEY_ID")
    if values.get("DJANGO_DEBUG") not in {None, "", "false"}:
        errors.append("DJANGO_DEBUG must be false")
    if values.get("DJANGO_SECURE_SSL_REDIRECT") not in {None, "", "true"}:
        errors.append("DJANGO_SECURE_SSL_REDIRECT must be true")
    if values.get("AUTH_CACHE_URL") not in {
        None,
        "",
        "redis://redis:6379/4",
    }:
        errors.append("AUTH_CACHE_URL must be redis://redis:6379/4")
    jwt_key = values.get("JWT_SIGNING_KEY", "")
    if jwt_key and len(jwt_key) < 32:
        errors.append("JWT_SIGNING_KEY must contain at least 32 characters")
    if values.get("ASR_PROVIDER") not in {None, "", "funasr"}:
        errors.append("ASR_PROVIDER must be funasr")
    if values.get("ASR_LEASE_PROVIDER") not in {None, "", "redis"}:
        errors.append("ASR_LEASE_PROVIDER must be redis")
    if values.get("ASR_MODEL") not in {None, "", "paraformer-zh"}:
        errors.append("ASR_MODEL must be paraformer-zh")
    if values.get("ASR_BASE_URL") not in {
        None,
        "",
        "http://funasr:8000",
    }:
        errors.append("ASR_BASE_URL must be http://funasr:8000")
    if values.get("ASR_REDIS_URL") not in {
        None,
        "",
        "redis://redis:6379/0",
    }:
        errors.append("ASR_REDIS_URL must be redis://redis:6379/0")
    if values.get("ASR_THROTTLE_REDIS_URL") not in {
        None,
        "",
        "redis://redis:6379/2",
    }:
        errors.append(
            "ASR_THROTTLE_REDIS_URL must be redis://redis:6379/2"
        )
    if values.get("ASR_TRUSTED_PROXY_IPS") not in {
        None,
        "",
        "172.29.0.10",
    }:
        errors.append("ASR_TRUSTED_PROXY_IPS must be only 172.29.0.10")
    try:
        timeout = float(values.get("ASR_TIMEOUT_SECONDS") or "0")
        if not 8 <= timeout <= 75:
            raise ValueError
    except ValueError:
        timeout = 0
        errors.append("ASR_TIMEOUT_SECONDS must be between 8 and 75")
    try:
        max_audio = int(values.get("ASR_MAX_AUDIO_BYTES") or "0")
        if not 0 < max_audio <= 4 * 1024 * 1024:
            raise ValueError
    except ValueError:
        max_audio = 0
        errors.append("ASR_MAX_AUDIO_BYTES must be at most 4194304")
    try:
        max_request = int(values.get("ASR_MAX_REQUEST_BYTES") or "0")
        if not max_audio < max_request <= 5 * 1024 * 1024:
            raise ValueError
    except ValueError:
        errors.append(
            "ASR_MAX_REQUEST_BYTES must exceed audio bytes and be at most 5242880"
        )
    try:
        min_duration = float(
            values.get("ASR_MIN_DURATION_SECONDS") or "0"
        )
        if not 0 < min_duration <= 5:
            raise ValueError
    except ValueError:
        min_duration = 0
        errors.append("ASR_MIN_DURATION_SECONDS must be between 0 and 5")
    try:
        max_duration = float(
            values.get("ASR_MAX_DURATION_SECONDS") or "0"
        )
        if not min_duration < max_duration <= 60:
            raise ValueError
    except ValueError:
        errors.append(
            "ASR_MAX_DURATION_SECONDS must exceed minimum and be at most 60"
        )
    for key in ("ASR_GLOBAL_CONCURRENCY", "ASR_CONCURRENCY_PER_USER"):
        if values.get(key) not in {None, "", "1"}:
            errors.append(f"{key} must equal 1")
    try:
        lease_ttl = int(values.get("ASR_LEASE_TTL_SECONDS") or "0")
        if not timeout < lease_ttl <= 120:
            raise ValueError
    except ValueError:
        errors.append(
            "ASR_LEASE_TTL_SECONDS must exceed ASR_TIMEOUT_SECONDS"
        )
    for key in ("ASR_USER_RATE", "ASR_IP_RATE"):
        value = values.get(key)
        if value not in {None, ""} and not RATE_PATTERN.fullmatch(value):
            errors.append(f"{key} must be a positive DRF rate")
    if values.get("OCR_DEBUG_TEXT_LOGGING") not in {
        None,
        "",
        "true",
        "false",
    }:
        errors.append("OCR_DEBUG_TEXT_LOGGING must be true or false")
    if values.get("OCR_SEMANTIC_PROVIDER") not in {
        None,
        "",
        "deepseek",
        "none",
    }:
        errors.append("OCR_SEMANTIC_PROVIDER must be deepseek or none")
    try:
        semantic_timeout = float(
            values.get("OCR_SEMANTIC_TIMEOUT_SECONDS") or "8"
        )
        if semantic_timeout <= 0:
            raise ValueError
    except ValueError:
        errors.append(
            "OCR_SEMANTIC_TIMEOUT_SECONDS must be a positive number"
        )
    return errors


def main() -> int:
    if len(sys.argv) not in {2, 4} or (
        len(sys.argv) == 4 and sys.argv[2] != "--get"
    ):
        print("usage: check_env.py ENV_FILE [--get KEY]", file=sys.stderr)
        return 2

    try:
        values = parse_env(Path(sys.argv[1]))
        errors = validate(values)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    if len(sys.argv) == 4:
        key = sys.argv[3]
        if key not in values:
            print(f"{key} is not defined", file=sys.stderr)
            return 2
        print(values[key])
        return 0

    print("Production environment is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

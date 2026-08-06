#!/usr/bin/env python3
import sys
from pathlib import Path
from urllib.parse import urlparse


REQUIRED = {
    "DOMAIN",
    "FILES_DOMAIN",
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
    "OCR_PROVIDER",
    "OCR_STORAGE_PROVIDER",
    "OCR_JOB_RETENTION_HOURS",
    "OCR_QUEUE",
    "S3_INTERNAL_ENDPOINT",
    "S3_PUBLIC_ENDPOINT",
    "S3_BUCKET",
    "S3_REGION",
    "S3_ADDRESSING_STYLE",
    "S3_ACCESS_KEY_ID",
    "S3_SECRET_ACCESS_KEY",
    "MINIO_ROOT_USER",
    "MINIO_ROOT_PASSWORD",
    "CERTBOT_EMAIL",
    "BACKUP_DIR",
    "BACKUP_RETENTION_DAYS",
}


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
    if values.get("DOMAIN") not in {None, "", "aipupu.cloud"}:
        errors.append("DOMAIN must be aipupu.cloud")
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

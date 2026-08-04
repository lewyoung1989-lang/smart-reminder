#!/usr/bin/env python3
import sys
from pathlib import Path


REQUIRED = {
    "DOMAIN",
    "DJANGO_SECRET_KEY",
    "DJANGO_DEBUG",
    "DJANGO_ALLOWED_HOSTS",
    "DJANGO_CSRF_TRUSTED_ORIGINS",
    "POSTGRES_DB",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "CELERY_BROKER_URL",
    "CELERY_RESULT_BACKEND",
    "DEEPSEEK_API_KEY",
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
    if values.get("DJANGO_DEBUG") not in {None, "", "false"}:
        errors.append("DJANGO_DEBUG must be false")
    if values.get("DJANGO_SECURE_SSL_REDIRECT") not in {None, "", "true"}:
        errors.append("DJANGO_SECURE_SSL_REDIRECT must be true")
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

import os
from pathlib import Path

from dotenv import load_dotenv


def env_bool(name, default):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR.parent / ".env")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "local-development-only")
DEBUG = env_bool("DJANGO_DEBUG", True)
ALLOWED_HOSTS = [
    host.strip()
    for host in os.environ.get(
        "DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1,testserver"
    ).split(",")
    if host.strip()
]
CSRF_TRUSTED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("DJANGO_CSRF_TRUSTED_ORIGINS", "").split(",")
    if origin.strip()
]

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", False)
SESSION_COOKIE_SECURE = env_bool("DJANGO_SESSION_COOKIE_SECURE", not DEBUG)
CSRF_COOKIE_SECURE = env_bool("DJANGO_CSRF_COOKIE_SECURE", not DEBUG)
SECURE_HSTS_SECONDS = int(os.environ.get("DJANGO_SECURE_HSTS_SECONDS", "0"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = env_bool(
    "DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS", False
)
SECURE_HSTS_PRELOAD = env_bool("DJANGO_SECURE_HSTS_PRELOAD", False)

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "rest_framework",
    "rest_framework.authtoken",
    "apps.core",
    "apps.reminders",
    "apps.medicines.apps.MedicinesConfig",
    "apps.ocr.apps.OCRConfig",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

if os.environ.get("POSTGRES_HOST"):
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": os.environ.get("POSTGRES_DB", "smart_reminder"),
            "USER": os.environ.get("POSTGRES_USER", "smart_reminder"),
            "PASSWORD": os.environ.get("POSTGRES_PASSWORD", "local-development"),
            "HOST": os.environ["POSTGRES_HOST"],
            "PORT": os.environ.get("POSTGRES_PORT", "5432"),
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

AUTH_PASSWORD_VALIDATORS = []
LANGUAGE_CODE = "zh-hans"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "apps.core.authentication.BearerTokenAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
}

CELERY_BROKER_URL = os.environ.get("CELERY_BROKER_URL", "redis://localhost:6379/0")
CELERY_RESULT_BACKEND = os.environ.get("CELERY_RESULT_BACKEND", "redis://localhost:6379/1")
CELERY_TASK_SERIALIZER = "json"
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TIMEZONE = "UTC"

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
DEEPSEEK_BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
DEEPSEEK_MODEL = os.environ.get("DEEPSEEK_MODEL", "deepseek-v4-flash")
DEEPSEEK_TIMEOUT_SECONDS = float(os.environ.get("DEEPSEEK_TIMEOUT_SECONDS", "8"))

OCR_PROVIDER = os.environ.get("OCR_PROVIDER", "rapidocr")
OCR_LANGUAGE = os.environ.get("OCR_LANGUAGE", "ch")
OCR_TEXT_SCORE = float(os.environ.get("OCR_TEXT_SCORE", "0.50"))
OCR_MAX_IMAGE_BYTES = int(os.environ.get("OCR_MAX_IMAGE_BYTES", str(8 * 1024 * 1024)))
OCR_MAX_IMAGE_SIDE = int(os.environ.get("OCR_MAX_IMAGE_SIDE", "2048"))
OCR_JOB_RETENTION_HOURS = int(os.environ.get("OCR_JOB_RETENTION_HOURS", "24"))
OCR_WORKER_CONCURRENCY = int(os.environ.get("OCR_WORKER_CONCURRENCY", "1"))
OCR_TASK_SOFT_TIME_LIMIT = int(os.environ.get("OCR_TASK_SOFT_TIME_LIMIT", "45"))
OCR_TASK_TIME_LIMIT = int(os.environ.get("OCR_TASK_TIME_LIMIT", "60"))
OCR_MAX_RETRIES = int(os.environ.get("OCR_MAX_RETRIES", "2"))
OCR_MODEL_ROOT = os.environ.get("OCR_MODEL_ROOT", "")
OCR_QUEUE = os.environ.get("OCR_QUEUE", "ocr")
OCR_STORAGE_PROVIDER = os.environ.get("OCR_STORAGE_PROVIDER", "s3")
OCR_UPLOAD_URL_TTL_SECONDS = int(os.environ.get("OCR_UPLOAD_URL_TTL_SECONDS", "600"))

S3_INTERNAL_ENDPOINT = os.environ.get(
    "S3_INTERNAL_ENDPOINT",
    os.environ.get("S3_ENDPOINT", "http://localhost:9000"),
)
S3_PUBLIC_ENDPOINT = os.environ.get(
    "S3_PUBLIC_ENDPOINT",
    S3_INTERNAL_ENDPOINT,
)
S3_BUCKET = os.environ.get("S3_BUCKET", "smart-reminder-private")
S3_REGION = os.environ.get("S3_REGION", "us-east-1")
S3_ADDRESSING_STYLE = os.environ.get("S3_ADDRESSING_STYLE", "path")
S3_ACCESS_KEY_ID = os.environ.get("S3_ACCESS_KEY_ID", "")
S3_SECRET_ACCESS_KEY = os.environ.get("S3_SECRET_ACCESS_KEY", "")

CELERY_TASK_ROUTES = {"apps.ocr.tasks.*": {"queue": OCR_QUEUE}}
CELERY_TASK_SOFT_TIME_LIMIT = OCR_TASK_SOFT_TIME_LIMIT
CELERY_TASK_TIME_LIMIT = OCR_TASK_TIME_LIMIT
CELERY_BEAT_SCHEDULE = {
    "purge-expired-ocr-images-hourly": {
        "task": "apps.ocr.tasks.purge_expired_ocr_images",
        "schedule": 3600.0,
    },
}

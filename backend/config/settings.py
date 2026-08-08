import os
from datetime import timedelta
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv


def env_bool(name, default):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _positive_int_setting(name, value):
    parsed = int(value)
    if parsed <= 0:
        raise ImproperlyConfigured(f"{name} must be positive")
    return parsed


BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR.parent / ".env")

SECRET_KEY = os.environ.get(
    "DJANGO_SECRET_KEY",
    "local-development-only-key-not-for-production-use",
)
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

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").strip().upper()
if LOG_LEVEL not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
    raise ValueError("LOG_LEVEL must be DEBUG, INFO, WARNING, ERROR, or CRITICAL")

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "production": {
            "format": (
                "%(asctime)s level=%(levelname)s logger=%(name)s "
                "message=%(message)s"
            ),
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "production",
        },
    },
    "root": {
        "handlers": ["console"],
        "level": LOG_LEVEL,
    },
}

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "rest_framework",
    "rest_framework.authtoken",
    "rest_framework_simplejwt.token_blacklist",
    "apps.accounts.apps.AccountsConfig",
    "apps.core",
    "apps.reminders",
    "apps.workflows.apps.WorkflowsConfig",
    "apps.voice",
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

AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": (
            "django.contrib.auth.password_validation."
            "UserAttributeSimilarityValidator"
        ),
    },
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 8},
    },
    {
        "NAME": "django.contrib.auth.password_validation.CommonPasswordValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.NumericPasswordValidator",
    },
]
LANGUAGE_CODE = "zh-hans"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "apps.core.authentication.CompositeBearerAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
}

AUTH_CACHE_URL = os.environ.get("AUTH_CACHE_URL", "")
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "smart-reminder-default",
    },
    "auth": (
        {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": AUTH_CACHE_URL,
            "TIMEOUT": None,
        }
        if AUTH_CACHE_URL
        else {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "smart-reminder-auth",
        }
    ),
}
AUTH_RATE_LIMITS = {
    "register_ip": (5, 60 * 60),
    "register_phone": (3, 24 * 60 * 60),
    "login_combo": (5, 15 * 60),
    "login_ip": (30, 60 * 60),
    "refresh_ip": (30, 5 * 60),
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=15),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=30),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": False,
    "ALGORITHM": "HS256",
    "SIGNING_KEY": os.environ.get("JWT_SIGNING_KEY", SECRET_KEY),
    "AUTH_HEADER_TYPES": ("Bearer",),
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

ASR_PROVIDER = os.environ.get("ASR_PROVIDER", "funasr")
ASR_BASE_URL = os.environ.get("ASR_BASE_URL", "http://localhost:18001")
ASR_MODEL = os.environ.get("ASR_MODEL", "paraformer-zh")
ASR_TIMEOUT_SECONDS = float(os.environ.get("ASR_TIMEOUT_SECONDS", "20"))
ASR_MAX_AUDIO_BYTES = int(os.environ.get("ASR_MAX_AUDIO_BYTES", str(4 * 1024 * 1024)))
ASR_MAX_REQUEST_BYTES = int(os.environ.get("ASR_MAX_REQUEST_BYTES", str(5 * 1024 * 1024)))
ASR_MIN_DURATION_SECONDS = float(os.environ.get("ASR_MIN_DURATION_SECONDS", "0.3"))
ASR_MAX_DURATION_SECONDS = float(os.environ.get("ASR_MAX_DURATION_SECONDS", "20"))
ASR_GLOBAL_CONCURRENCY = int(os.environ.get("ASR_GLOBAL_CONCURRENCY", "1"))
ASR_CONCURRENCY_PER_USER = int(os.environ.get("ASR_CONCURRENCY_PER_USER", "1"))
if ASR_GLOBAL_CONCURRENCY != 1 or ASR_CONCURRENCY_PER_USER != 1:
    raise ImproperlyConfigured("V1 only supports ASR concurrency of 1")
ASR_LEASE_TTL_SECONDS = int(os.environ.get("ASR_LEASE_TTL_SECONDS", "25"))
ASR_USER_RATE = os.environ.get("ASR_USER_RATE", "10/min")
ASR_IP_RATE = os.environ.get("ASR_IP_RATE", "30/min")
ASR_REDIS_URL = os.environ.get("ASR_REDIS_URL", CELERY_BROKER_URL)
ASR_THROTTLE_REDIS_URL = os.environ.get("ASR_THROTTLE_REDIS_URL", "")
ASR_TRUSTED_PROXY_IPS = [
    address.strip()
    for address in os.environ.get("ASR_TRUSTED_PROXY_IPS", "").split(",")
    if address.strip()
]

if ASR_THROTTLE_REDIS_URL:
    CACHES["asr_throttle"] = {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": ASR_THROTTLE_REDIS_URL,
        "KEY_PREFIX": "smart-reminder-asr-throttle",
    }
else:
    CACHES["asr_throttle"] = {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "smart-reminder-asr-throttle",
    }

REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {
    "voice_transcription_user": ASR_USER_RATE,
    "voice_transcription_ip": ASR_IP_RATE,
}

OCR_ENABLED = os.environ.get("OCR_ENABLED", "true").lower() == "true"
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
OCR_DEBUG_TEXT_LOGGING = (
    os.environ.get("OCR_DEBUG_TEXT_LOGGING", "false").lower() == "true"
)
OCR_SEMANTIC_PROVIDER = os.environ.get("OCR_SEMANTIC_PROVIDER", "deepseek")
OCR_SEMANTIC_TIMEOUT_SECONDS = float(
    os.environ.get("OCR_SEMANTIC_TIMEOUT_SECONDS", "8")
)
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
OUTBOX_LEASE_SECONDS = _positive_int_setting(
    "OUTBOX_LEASE_SECONDS", os.environ.get("OUTBOX_LEASE_SECONDS", "60")
)
OUTBOX_PUBLISH_BATCH_SIZE = _positive_int_setting(
    "OUTBOX_PUBLISH_BATCH_SIZE", os.environ.get("OUTBOX_PUBLISH_BATCH_SIZE", "100")
)
NOTIFICATION_PUBLISHER = os.environ.get(
    "NOTIFICATION_PUBLISHER",
    "apps.workflows.services.outbox.InAppNotificationPublisher",
)
CELERY_BEAT_SCHEDULE = {
    "dispatch-due-workflows-minute": {
        "task": "apps.workflows.tasks.dispatch_due_workflows_task",
        "schedule": 60.0,
    },
    "publish-due-outbox-minute": {
        "task": "apps.workflows.tasks.publish_due_outbox_task",
        "schedule": 60.0,
    },
    "purge-expired-ocr-images-hourly": {
        "task": "apps.ocr.tasks.purge_expired_ocr_images",
        "schedule": 3600.0,
    },
}

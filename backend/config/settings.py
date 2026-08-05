import os
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR.parent / ".env")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "local-development-only")
DEBUG = os.environ.get("DJANGO_DEBUG", "true").lower() == "true"
ALLOWED_HOSTS = [host for host in os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1,testserver").split(",") if host]

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "rest_framework",
    "rest_framework.authtoken",
    "apps.core",
    "apps.reminders",
    "apps.voice",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
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

if ASR_THROTTLE_REDIS_URL:
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": ASR_THROTTLE_REDIS_URL,
            "KEY_PREFIX": "smart-reminder-asr-throttle",
        }
    }

REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {
    "voice_transcription_user": ASR_USER_RATE,
    "voice_transcription_ip": ASR_IP_RATE,
}

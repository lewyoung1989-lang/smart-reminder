import os
import subprocess
import sys
import textwrap
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parents[2]


def test_production_security_settings_are_loaded_from_environment():
    env = os.environ.copy()
    env.update(
        {
            "DJANGO_DEBUG": "false",
            "DJANGO_ALLOWED_HOSTS": "aipupu.cloud",
            "DJANGO_CSRF_TRUSTED_ORIGINS": "https://aipupu.cloud",
            "DJANGO_SECURE_SSL_REDIRECT": "true",
            "DJANGO_SECURE_HSTS_SECONDS": "3600",
            "LOG_LEVEL": "WARNING",
            "AUTH_CACHE_URL": "redis://redis:6379/4",
            "JWT_SIGNING_KEY": "test-jwt-signing-secret-at-least-32-bytes",
        }
    )
    script = textwrap.dedent(
        """
        from config import settings

        assert settings.DEBUG is False
        assert settings.ALLOWED_HOSTS == ["aipupu.cloud"]
        assert settings.CSRF_TRUSTED_ORIGINS == ["https://aipupu.cloud"]
        assert settings.SECURE_PROXY_SSL_HEADER == (
            "HTTP_X_FORWARDED_PROTO",
            "https",
        )
        assert settings.SECURE_SSL_REDIRECT is True
        assert settings.SESSION_COOKIE_SECURE is True
        assert settings.CSRF_COOKIE_SECURE is True
        assert settings.SECURE_HSTS_SECONDS == 3600
        assert "django.middleware.csrf.CsrfViewMiddleware" in settings.MIDDLEWARE
        assert (
            "django.middleware.clickjacking.XFrameOptionsMiddleware"
            in settings.MIDDLEWARE
        )
        assert settings.LOGGING["handlers"] == {
            "console": {
                "class": "logging.StreamHandler",
                "formatter": "production",
            }
        }
        assert settings.LOGGING["root"]["handlers"] == ["console"]
        assert settings.LOGGING["root"]["level"] == "WARNING"
        assert settings.LOGGING["formatters"]["production"]["format"] == (
            "%(asctime)s level=%(levelname)s logger=%(name)s "
            "message=%(message)s"
        )
        assert settings.CACHES["auth"]["BACKEND"] == (
            "django.core.cache.backends.redis.RedisCache"
        )
        assert settings.CACHES["auth"]["LOCATION"] == "redis://redis:6379/4"
        assert settings.SIMPLE_JWT["SIGNING_KEY"] == (
            "test-jwt-signing-secret-at-least-32-bytes"
        )
        """
    )

    subprocess.run(
        [sys.executable, "-c", script],
        cwd=BACKEND_DIR,
        env=env,
        check=True,
    )

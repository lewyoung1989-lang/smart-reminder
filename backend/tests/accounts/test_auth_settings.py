from datetime import timedelta

from django.conf import settings


def test_jwt_lifetimes_and_rotation_are_configured():
    assert settings.SIMPLE_JWT["ACCESS_TOKEN_LIFETIME"] == timedelta(minutes=15)
    assert settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"] == timedelta(days=30)
    assert settings.SIMPLE_JWT["ROTATE_REFRESH_TOKENS"] is True
    assert settings.SIMPLE_JWT["BLACKLIST_AFTER_ROTATION"] is True


def test_default_password_validators_are_enabled():
    validator_names = {
        entry["NAME"].rsplit(".", 1)[-1]
        for entry in settings.AUTH_PASSWORD_VALIDATORS
    }
    assert validator_names == {
        "UserAttributeSimilarityValidator",
        "MinimumLengthValidator",
        "CommonPasswordValidator",
        "NumericPasswordValidator",
    }

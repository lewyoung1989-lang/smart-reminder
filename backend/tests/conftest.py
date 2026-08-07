import pytest
from django.core.cache import caches
from rest_framework.test import APIClient


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture(autouse=True)
def isolate_rate_limit_caches():
    caches["auth"].clear()
    caches["asr_throttle"].clear()
    yield
    caches["auth"].clear()
    caches["asr_throttle"].clear()


@pytest.fixture
def user(django_user_model):
    return django_user_model.objects.create_user(
        username="voice-tester",
        password="test-password",
    )

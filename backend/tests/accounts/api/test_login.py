import pytest
from django.contrib.auth import get_user_model

from apps.accounts.models import PhoneIdentity


LOGIN_URL = "/api/v1/auth/login"
VALID_PASSWORD = "Good-pass-2026"


@pytest.fixture
def phone_user(db):
    user = get_user_model().objects.create_user(
        username="+8613800138000",
        password=VALID_PASSWORD,
    )
    PhoneIdentity.objects.create(user=user, phone_e164=user.username)
    return user


@pytest.mark.django_db
def test_logs_in_with_phone_and_password(api_client, phone_user):
    response = api_client.post(
        LOGIN_URL,
        {"phone": "13800138000", "password": VALID_PASSWORD},
        format="json",
    )

    assert response.status_code == 200
    assert response.data["user"]["phone_masked"] == "138****8000"
    assert response.data["access_token"]
    assert response.data["refresh_token"]


@pytest.mark.django_db
@pytest.mark.parametrize("phone", ["13900139000", "13800138000"])
def test_login_hides_account_and_password_state(api_client, phone_user, phone):
    response = api_client.post(
        LOGIN_URL,
        {"phone": phone, "password": "Wrong-pass-2026"},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_credentials"}


@pytest.mark.django_db
def test_login_hides_inactive_account_state(api_client, phone_user):
    phone_user.is_active = False
    phone_user.save(update_fields=["is_active"])

    response = api_client.post(
        LOGIN_URL,
        {"phone": "13800138000", "password": VALID_PASSWORD},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_credentials"}

import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import PhoneIdentity


@pytest.fixture
def phone_user(db):
    user = get_user_model().objects.create_user(
        username="+8613800138000",
        password="Old-pass-2026",
    )
    PhoneIdentity.objects.create(user=user, phone_e164=user.username)
    return user


def refresh_status(refresh_token):
    return APIClient().post(
        "/api/v1/auth/refresh",
        {"refresh_token": refresh_token},
        format="json",
    ).status_code


@pytest.mark.django_db
def test_password_change_revokes_all_old_refresh_tokens(api_client, phone_user):
    old_tokens = [str(RefreshToken.for_user(phone_user)) for _ in range(2)]
    api_client.force_authenticate(user=phone_user)

    response = api_client.post(
        "/api/v1/auth/password/change",
        {
            "current_password": "Old-pass-2026",
            "new_password": "New-pass-2026",
            "new_password_confirm": "New-pass-2026",
        },
        format="json",
    )

    assert response.status_code == 200
    assert response.data["access_token"]
    assert response.data["refresh_token"]
    assert all(refresh_status(token) == 401 for token in old_tokens)
    phone_user.refresh_from_db()
    assert phone_user.check_password("New-pass-2026")


@pytest.mark.django_db
def test_password_change_rejects_wrong_current_password(api_client, phone_user):
    api_client.force_authenticate(user=phone_user)

    response = api_client.post(
        "/api/v1/auth/password/change",
        {
            "current_password": "Wrong-pass-2026",
            "new_password": "New-pass-2026",
            "new_password_confirm": "New-pass-2026",
        },
        format="json",
    )

    assert response.status_code == 400
    assert response.data == {
        "code": "invalid_current_password",
        "field": "current_password",
    }

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
def test_logout_blacklists_only_submitted_refresh(api_client, phone_user):
    first = str(RefreshToken.for_user(phone_user))
    second = str(RefreshToken.for_user(phone_user))
    api_client.force_authenticate(user=phone_user)

    response = api_client.post(
        "/api/v1/auth/logout",
        {"refresh_token": first},
        format="json",
    )

    assert response.status_code == 204
    assert refresh_status(first) == 401
    assert refresh_status(second) == 200


@pytest.mark.django_db
def test_logout_is_idempotent_for_same_device(api_client, phone_user):
    refresh = str(RefreshToken.for_user(phone_user))
    api_client.force_authenticate(user=phone_user)

    first = api_client.post(
        "/api/v1/auth/logout",
        {"refresh_token": refresh},
        format="json",
    )
    second = api_client.post(
        "/api/v1/auth/logout",
        {"refresh_token": refresh},
        format="json",
    )

    assert first.status_code == 204
    assert second.status_code == 204


@pytest.mark.django_db
def test_logout_rejects_another_users_refresh(api_client, phone_user):
    other = get_user_model().objects.create_user(username="other")
    other_refresh = str(RefreshToken.for_user(other))
    api_client.force_authenticate(user=phone_user)

    response = api_client.post(
        "/api/v1/auth/logout",
        {"refresh_token": other_refresh},
        format="json",
    )

    assert response.status_code == 400
    assert response.data == {"code": "invalid_refresh_token"}

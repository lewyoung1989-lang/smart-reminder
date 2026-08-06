import time

import jwt
import pytest
from django.contrib.auth import get_user_model


REGISTER_URL = "/api/v1/auth/register"
REFRESH_URL = "/api/v1/auth/refresh"
VALID_PASSWORD = "Good-pass-2026"


@pytest.fixture
def registered_tokens(api_client, db):
    response = api_client.post(
        REGISTER_URL,
        {
            "phone": "13800138000",
            "password": VALID_PASSWORD,
            "password_confirm": VALID_PASSWORD,
        },
        format="json",
    )
    return response.data


def test_refresh_rotates_token_and_rejects_replay(api_client, registered_tokens):
    old_refresh = registered_tokens["refresh_token"]

    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": old_refresh},
        format="json",
    )

    assert response.status_code == 200
    assert response.data["access_token"]
    assert response.data["refresh_token"] != old_refresh
    replay = api_client.post(
        REFRESH_URL,
        {"refresh_token": old_refresh},
        format="json",
    )
    assert replay.status_code == 401
    assert replay.data == {"code": "invalid_refresh_token"}


def test_refresh_serializes_rotation_with_user_row_lock(
    api_client,
    registered_tokens,
    mocker,
):
    manager = get_user_model().objects
    lock_spy = mocker.patch.object(
        manager,
        "select_for_update",
        wraps=manager.select_for_update,
    )

    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": registered_tokens["refresh_token"]},
        format="json",
    )

    assert response.status_code == 200
    lock_spy.assert_called_once_with()


def test_invalid_signature_is_rejected_before_user_row_lock(
    api_client,
    registered_tokens,
    mocker,
):
    user = get_user_model().objects.get(username="+8613800138000")
    invalid_refresh = jwt.encode(
        {
            "token_type": "refresh",
            "exp": int(time.time()) + 300,
            "iat": int(time.time()),
            "jti": "forged-token-id",
            "user_id": user.pk,
        },
        "wrong-signing-key-that-is-long-enough-for-hs256",
        algorithm="HS256",
    )
    manager = get_user_model().objects
    lock_spy = mocker.patch.object(
        manager,
        "select_for_update",
        wraps=manager.select_for_update,
    )

    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": invalid_refresh},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_refresh_token"}
    lock_spy.assert_not_called()


def test_invalid_user_claim_returns_stable_error(api_client, db):
    invalid_refresh = jwt.encode(
        {
            "token_type": "refresh",
            "exp": int(time.time()) + 300,
            "iat": int(time.time()),
            "jti": "forged-token-id",
            "user_id": "not-an-integer",
        },
        "wrong-signing-key-that-is-long-enough-for-hs256",
        algorithm="HS256",
    )
    api_client.raise_request_exception = False

    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": invalid_refresh},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_refresh_token"}


def test_inactive_user_refresh_uses_stable_session_expiry_error(
    api_client,
    registered_tokens,
):
    user = get_user_model().objects.get(username="+8613800138000")
    user.is_active = False
    user.save(update_fields=["is_active"])

    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": registered_tokens["refresh_token"]},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_refresh_token"}


@pytest.mark.django_db
def test_invalid_refresh_uses_stable_error(api_client):
    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": "not-a-token"},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_refresh_token"}

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


@pytest.mark.django_db
def test_invalid_refresh_uses_stable_error(api_client):
    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": "not-a-token"},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_refresh_token"}

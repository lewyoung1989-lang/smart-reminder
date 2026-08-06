import pytest


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


@pytest.mark.django_db
def test_invalid_refresh_uses_stable_error(api_client):
    response = api_client.post(
        REFRESH_URL,
        {"refresh_token": "not-a-token"},
        format="json",
    )

    assert response.status_code == 401
    assert response.data == {"code": "invalid_refresh_token"}

import pytest

from apps.accounts.models import PhoneIdentity


REGISTER_URL = "/api/v1/auth/register"
VALID_PASSWORD = "Good-pass-2026"


@pytest.mark.django_db
def test_registers_phone_user_and_returns_tokens(api_client):
    response = api_client.post(
        REGISTER_URL,
        {
            "phone": "13800138000",
            "password": VALID_PASSWORD,
            "password_confirm": VALID_PASSWORD,
        },
        format="json",
    )

    assert response.status_code == 201
    assert response.data["user"]["phone_masked"] == "138****8000"
    assert response.data["user"]["phone_verified"] is False
    assert response.data["access_token"]
    assert response.data["refresh_token"]
    assert response.data["access_expires_in"] == 900
    identity = PhoneIdentity.objects.get(phone_e164="+8613800138000")
    assert identity.user.username == "+8613800138000"
    assert identity.user.check_password(VALID_PASSWORD)


@pytest.mark.django_db
def test_duplicate_phone_returns_stable_conflict(api_client):
    payload = {
        "phone": "13800138000",
        "password": VALID_PASSWORD,
        "password_confirm": VALID_PASSWORD,
    }
    assert api_client.post(REGISTER_URL, payload, format="json").status_code == 201

    response = api_client.post(REGISTER_URL, payload, format="json")

    assert response.status_code == 409
    assert response.data == {"code": "phone_already_registered"}


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("payload", "code", "field"),
    [
        (
            {
                "phone": "12800138000",
                "password": VALID_PASSWORD,
                "password_confirm": VALID_PASSWORD,
            },
            "invalid_phone",
            "phone",
        ),
        (
            {
                "phone": "13800138000",
                "password": VALID_PASSWORD,
                "password_confirm": "Different-pass-2026",
            },
            "password_mismatch",
            "password_confirm",
        ),
        (
            {
                "phone": "13800138000",
                "password": "12345678",
                "password_confirm": "12345678",
            },
            "weak_password",
            "password",
        ),
    ],
)
def test_registration_validation_returns_stable_field_error(
    api_client,
    payload,
    code,
    field,
):
    response = api_client.post(REGISTER_URL, payload, format="json")

    assert response.status_code == 400
    assert response.data["code"] == code
    assert response.data["field"] == field

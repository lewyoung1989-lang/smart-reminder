import pytest

from apps.accounts.models import PhoneIdentity


@pytest.mark.django_db
def test_me_returns_only_safe_user_summary(api_client, user):
    identity = PhoneIdentity.objects.create(
        user=user,
        phone_e164="+8613800138000",
    )
    api_client.force_authenticate(user=user)

    response = api_client.get("/api/v1/auth/me")

    assert response.status_code == 200
    assert response.data == {
        "id": str(user.id),
        "phone_masked": "138****8000",
        "phone_verified": False,
    }
    assert identity.phone_e164 not in str(response.data)

import pytest
from rest_framework.authtoken.models import Token
from rest_framework_simplejwt.tokens import AccessToken


@pytest.mark.django_db
def test_jwt_bearer_authenticates_business_api(api_client, user):
    access = str(AccessToken.for_user(user))
    api_client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    response = api_client.get("/api/v1/reminders")

    assert response.status_code == 200


@pytest.mark.django_db
def test_legacy_drf_bearer_remains_compatible(api_client, user):
    token = Token.objects.create(user=user)
    api_client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.key}")

    response = api_client.get("/api/v1/reminders")

    assert response.status_code == 200


@pytest.mark.django_db
def test_malformed_jwt_never_falls_back_to_legacy(api_client, mocker):
    legacy = mocker.patch(
        "apps.core.authentication.LegacyBearerTokenAuthentication."
        "authenticate_credentials"
    )
    api_client.credentials(HTTP_AUTHORIZATION="Bearer aaa.bbb.ccc")

    response = api_client.get("/api/v1/reminders")

    assert response.status_code == 401
    legacy.assert_not_called()
    assert response.headers["WWW-Authenticate"] == "Bearer"

import pytest


@pytest.mark.django_db
def test_login_failure_log_excludes_credentials_and_complete_phone(
    api_client,
    caplog,
):
    with caplog.at_level("INFO", logger="apps.accounts.api.views"):
        response = api_client.post(
            "/api/v1/auth/login",
            {"phone": "13800138000", "password": "Secret-pass-2026"},
            format="json",
        )

    assert response.status_code == 401
    assert "auth_login_failed" in caplog.text
    assert "13800138000" not in caplog.text
    assert "Secret-pass-2026" not in caplog.text

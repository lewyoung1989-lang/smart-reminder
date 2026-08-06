import pytest
from django.core.cache import caches


VALID_PASSWORD = "Good-pass-2026"


@pytest.fixture(autouse=True)
def clear_auth_cache():
    caches["auth"].clear()
    yield
    caches["auth"].clear()


@pytest.mark.django_db
def test_registration_is_limited_by_ip(api_client, settings):
    settings.AUTH_RATE_LIMITS = {
        **settings.AUTH_RATE_LIMITS,
        "register_ip": (2, 3600),
        "register_phone": (10, 86400),
    }
    for phone in ("13800138000", "13900139000"):
        assert api_client.post(
            "/api/v1/auth/register",
            {
                "phone": phone,
                "password": VALID_PASSWORD,
                "password_confirm": VALID_PASSWORD,
            },
            format="json",
        ).status_code == 201

    response = api_client.post(
        "/api/v1/auth/register",
        {
            "phone": "13700137000",
            "password": VALID_PASSWORD,
            "password_confirm": VALID_PASSWORD,
        },
        format="json",
    )

    assert response.status_code == 429
    assert response.data["code"] == "rate_limited"
    assert response.data["retry_after"] > 0


@pytest.mark.django_db
def test_rate_limit_retry_uses_only_the_limited_dimension(
    api_client,
    settings,
    mocker,
):
    mocker.patch("apps.accounts.throttling.time.time", return_value=100)
    settings.AUTH_RATE_LIMITS = {
        **settings.AUTH_RATE_LIMITS,
        "register_ip": (0, 60),
        "register_phone": (10, 3600),
    }

    response = api_client.post(
        "/api/v1/auth/register",
        {
            "phone": "13800138000",
            "password": VALID_PASSWORD,
            "password_confirm": VALID_PASSWORD,
        },
        format="json",
    )

    assert response.status_code == 429
    assert response.data["retry_after"] == 20


@pytest.mark.django_db
def test_login_failures_are_limited_and_success_clears_combo(
    api_client,
    settings,
):
    settings.AUTH_RATE_LIMITS = {
        **settings.AUTH_RATE_LIMITS,
        "login_combo": (2, 900),
        "login_ip": (20, 3600),
    }
    register = {
        "phone": "13800138000",
        "password": VALID_PASSWORD,
        "password_confirm": VALID_PASSWORD,
    }
    assert api_client.post(
        "/api/v1/auth/register",
        register,
        format="json",
    ).status_code == 201
    for _ in range(2):
        assert api_client.post(
            "/api/v1/auth/login",
            {"phone": register["phone"], "password": "Wrong-pass-2026"},
            format="json",
        ).status_code == 401

    limited = api_client.post(
        "/api/v1/auth/login",
        {"phone": register["phone"], "password": "Wrong-pass-2026"},
        format="json",
    )
    assert limited.status_code == 429

    caches["auth"].clear()
    success = api_client.post(
        "/api/v1/auth/login",
        {"phone": register["phone"], "password": VALID_PASSWORD},
        format="json",
    )
    assert success.status_code == 200


@pytest.mark.django_db
def test_auth_cache_keys_do_not_contain_complete_phone(api_client):
    api_client.post(
        "/api/v1/auth/login",
        {"phone": "13800138000", "password": "Wrong-pass-2026"},
        format="json",
    )

    keys = " ".join(str(key) for key in caches["auth"]._cache.keys())
    assert "13800138000" not in keys
    assert "+8613800138000" not in keys

from io import StringIO

import pytest
from django.contrib.auth import get_user_model
from django.core.management import call_command
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import PhoneIdentity


@pytest.mark.django_db
def test_reset_phone_password_is_interactive_and_revokes_refresh(mocker):
    user = get_user_model().objects.create_user(
        username="+8613800138000",
        password="Old-pass-2026",
    )
    PhoneIdentity.objects.create(user=user, phone_e164=user.username)
    old_refresh = str(RefreshToken.for_user(user))
    getpass_mock = mocker.patch(
        "getpass.getpass",
        side_effect=["Admin-reset-2026", "Admin-reset-2026"],
    )
    manager = get_user_model().objects
    lock_spy = mocker.patch.object(
        manager,
        "select_for_update",
        wraps=manager.select_for_update,
    )
    output = StringIO()

    call_command("reset_phone_password", "13800138000", stdout=output)

    user.refresh_from_db()
    assert user.check_password("Admin-reset-2026")
    assert getpass_mock.call_count == 2
    assert "Admin-reset-2026" not in output.getvalue()
    lock_spy.assert_called_once_with()
    response = APIClient().post(
        "/api/v1/auth/refresh",
        {"refresh_token": old_refresh},
        format="json",
    )
    assert response.status_code == 401

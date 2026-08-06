from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from django.contrib.auth import get_user_model
from django.db import close_old_connections, connection
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import PhoneIdentity


pytestmark = [
    pytest.mark.django_db(transaction=True),
    pytest.mark.skipif(
        not connection.features.has_select_for_update,
        reason="Concurrent row-lock tests require PostgreSQL",
    ),
]


def _run_concurrently(*operations):
    barrier = Barrier(len(operations))

    def run(operation):
        close_old_connections()
        try:
            barrier.wait()
            return operation()
        finally:
            close_old_connections()

    with ThreadPoolExecutor(max_workers=len(operations)) as executor:
        return [
            future.result()
            for future in [
                executor.submit(run, operation) for operation in operations
            ]
        ]


def test_concurrent_refresh_allows_only_one_rotation():
    user = get_user_model().objects.create_user(
        username="+8613800138000",
        password="Old-pass-2026",
    )
    PhoneIdentity.objects.create(user=user, phone_e164=user.username)
    old_refresh = str(RefreshToken.for_user(user))

    def refresh():
        return APIClient().post(
            "/api/v1/auth/refresh",
            {"refresh_token": old_refresh},
            format="json",
        )

    responses = _run_concurrently(refresh, refresh)

    assert sorted(response.status_code for response in responses) == [200, 401]


def test_password_change_revokes_refresh_successor_created_during_race():
    user = get_user_model().objects.create_user(
        username="+8613800138000",
        password="Old-pass-2026",
    )
    PhoneIdentity.objects.create(user=user, phone_e164=user.username)
    old_refresh = str(RefreshToken.for_user(user))

    def refresh():
        return APIClient().post(
            "/api/v1/auth/refresh",
            {"refresh_token": old_refresh},
            format="json",
        )

    def change_password():
        client = APIClient()
        client.force_authenticate(user=user)
        return client.post(
            "/api/v1/auth/password/change",
            {
                "current_password": "Old-pass-2026",
                "new_password": "New-pass-2026",
                "new_password_confirm": "New-pass-2026",
            },
            format="json",
        )

    refresh_response, password_response = _run_concurrently(
        refresh,
        change_password,
    )

    assert password_response.status_code == 200
    assert refresh_response.status_code in {200, 401}
    if refresh_response.status_code == 200:
        successor = refresh_response.data["refresh_token"]
        replay = APIClient().post(
            "/api/v1/auth/refresh",
            {"refresh_token": successor},
            format="json",
        )
        assert replay.status_code == 401

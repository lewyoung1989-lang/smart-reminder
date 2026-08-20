from datetime import datetime, timedelta, timezone as datetime_timezone
from urllib.parse import urlsplit

import pytest
from django.utils import timezone

from apps.reminders.models import ReminderDraft, ReminderRule, VoiceParseSession


NOW = datetime(2026, 8, 5, 4, 0, tzinfo=datetime_timezone.utc)


def create_rule(
    *,
    owner,
    title,
    scheduled_at,
    cancelled_at=None,
    completed_at=None,
    enabled=True,
):
    session = VoiceParseSession.objects.create(
        user=owner,
        transcript_sha256=title.encode().hex().ljust(64, "0")[:64],
        expires_at=NOW + timedelta(days=1),
    )
    draft = ReminderDraft.objects.create(
        session=session,
        draft_json={},
        expires_at=NOW + timedelta(days=1),
    )
    return ReminderRule.objects.create(
        owner=owner,
        title=title,
        timezone="Asia/Shanghai",
        schedule_json={"local_datetime": scheduled_at.isoformat()},
        severity="notification",
        scheduled_at=scheduled_at,
        cancelled_at=cancelled_at,
        completed_at=completed_at,
        enabled=enabled,
        source_draft=draft,
    )


@pytest.mark.django_db
def test_reminder_list_requires_authentication(api_client):
    response = api_client.get("/api/v1/reminders")

    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


@pytest.mark.django_db
def test_pending_is_default_owner_scoped_and_ordered_ascending(
    api_client,
    user,
    django_user_model,
    mocker,
):
    other = django_user_model.objects.create_user(username="other-reminder-owner")
    create_rule(
        owner=other,
        title="other",
        scheduled_at=NOW + timedelta(minutes=1),
    )
    create_rule(
        owner=user,
        title="later",
        scheduled_at=NOW + timedelta(minutes=20),
    )
    create_rule(
        owner=user,
        title="next",
        scheduled_at=NOW + timedelta(minutes=5),
    )
    create_rule(owner=user, title="boundary", scheduled_at=NOW)
    mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/reminders")

    assert response.status_code == 200
    assert [item["title"] for item in response.json()["results"]] == [
        "next",
        "later",
    ]
    assert all(item["status"] == "pending" for item in response.json()["results"])


@pytest.mark.django_db
def test_expired_includes_boundary_and_orders_descending(
    api_client,
    user,
    mocker,
):
    create_rule(
        owner=user,
        title="old",
        scheduled_at=NOW - timedelta(hours=1),
    )
    create_rule(owner=user, title="boundary", scheduled_at=NOW)
    create_rule(
        owner=user,
        title="recent",
        scheduled_at=NOW - timedelta(minutes=1),
    )
    mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/reminders", {"status": "expired"})

    assert response.status_code == 200
    assert [item["title"] for item in response.json()["results"]] == [
        "boundary",
        "recent",
        "old",
    ]
    assert all(item["status"] == "expired" for item in response.json()["results"])


@pytest.mark.django_db
def test_cancelled_orders_by_most_recent_cancellation(api_client, user, mocker):
    create_rule(
        owner=user,
        title="cancelled-first",
        scheduled_at=NOW + timedelta(hours=1),
        cancelled_at=NOW - timedelta(minutes=10),
        enabled=False,
    )
    create_rule(
        owner=user,
        title="cancelled-last",
        scheduled_at=NOW + timedelta(hours=1),
        cancelled_at=NOW - timedelta(minutes=1),
        enabled=False,
    )
    mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/reminders", {"status": "cancelled"})

    assert response.status_code == 200
    assert [item["title"] for item in response.json()["results"]] == [
        "cancelled-last",
        "cancelled-first",
    ]
    assert all(item["status"] == "cancelled" for item in response.json()["results"])


@pytest.mark.django_db
def test_completed_orders_by_most_recent_completion(api_client, user, mocker):
    create_rule(
        owner=user,
        title="completed-first",
        scheduled_at=NOW - timedelta(hours=1),
        completed_at=NOW - timedelta(minutes=10),
        enabled=False,
    )
    create_rule(
        owner=user,
        title="completed-last",
        scheduled_at=NOW - timedelta(hours=1),
        completed_at=NOW - timedelta(minutes=1),
        enabled=False,
    )
    mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/reminders", {"status": "completed"})

    assert response.status_code == 200
    assert [item["title"] for item in response.json()["results"]] == [
        "completed-last",
        "completed-first",
    ]
    assert all(item["status"] == "completed" for item in response.json()["results"])


@pytest.mark.django_db
def test_invalid_reminder_status_returns_400(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/reminders", {"status": "unknown"})

    assert response.status_code == 400


@pytest.mark.django_db
def test_reminder_list_uses_fifty_item_cursor_pages(api_client, user, mocker):
    for index in range(51):
        create_rule(
            owner=user,
            title=f"reminder-{index:02d}",
            scheduled_at=NOW + timedelta(minutes=index + 1),
        )
    mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    first = api_client.get("/api/v1/reminders", {"status": "pending"})

    assert first.status_code == 200
    assert len(first.json()["results"]) == 50
    assert first.json()["next"] is not None
    next_url = urlsplit(first.json()["next"])
    second = api_client.get(f"{next_url.path}?{next_url.query}")
    assert second.status_code == 200
    assert len(second.json()["results"]) == 1
    ids = [item["id"] for item in first.json()["results"] + second.json()["results"]]
    assert len(ids) == len(set(ids)) == 51

from datetime import datetime, timedelta, timezone as datetime_timezone

import pytest

from apps.reminders.models import ReminderDraft, ReminderRule, VoiceParseSession


NOW = datetime(2026, 8, 5, 4, 0, tzinfo=datetime_timezone.utc)


def create_rule(*, owner, title="喝水", scheduled_at=None, **overrides):
    scheduled_at = scheduled_at or NOW
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
    values = {
        "owner": owner,
        "title": title,
        "timezone": "Asia/Shanghai",
        "schedule_json": {"local_datetime": scheduled_at.isoformat()},
        "severity": "notification",
        "scheduled_at": scheduled_at,
        "source_draft": draft,
    }
    values.update(overrides)
    return ReminderRule.objects.create(**values)


@pytest.mark.django_db
def test_complete_reminder_is_idempotent_and_removes_it_from_pending(
    api_client, user, mocker
):
    rule = create_rule(owner=user, scheduled_at=NOW - timedelta(minutes=5))
    now_mock = mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    first = api_client.post(
        f"/api/v1/reminders/{rule.id}/actions",
        {"action": "complete"},
    )
    now_mock.return_value = NOW + timedelta(minutes=1)
    second = api_client.post(
        f"/api/v1/reminders/{rule.id}/actions",
        {"action": "complete"},
    )

    assert first.status_code == second.status_code == 200
    assert first.json()["status"] == second.json()["status"] == "completed"
    assert first.json()["completed_at"] == second.json()["completed_at"]
    rule.refresh_from_db()
    assert rule.enabled is False
    assert rule.completed_at == NOW


@pytest.mark.django_db
def test_snooze_reminder_moves_it_to_a_future_time(api_client, user, mocker):
    rule = create_rule(owner=user, scheduled_at=NOW - timedelta(minutes=5))
    mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/reminders/{rule.id}/actions",
        {"action": "snooze", "snooze_minutes": 30},
    )

    assert response.status_code == 200
    assert response.json()["status"] == "pending"
    assert response.json()["scheduled_at"] == "2026-08-05T04:30:00Z"
    rule.refresh_from_db()
    assert rule.enabled is True
    assert rule.cancelled_at is None
    assert rule.completed_at is None
    assert rule.scheduled_at == NOW + timedelta(minutes=30)
    assert rule.schedule_json["local_datetime"] == "2026-08-05T12:30:00+08:00"


@pytest.mark.django_db
def test_snooze_rejects_unsupported_duration(api_client, user):
    rule = create_rule(owner=user)
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/reminders/{rule.id}/actions",
        {"action": "snooze", "snooze_minutes": 5},
    )

    assert response.status_code == 400


@pytest.mark.django_db
def test_reminder_actions_are_owner_scoped(api_client, user, django_user_model):
    other = django_user_model.objects.create_user(username="reminder-action-other")
    rule = create_rule(owner=other)
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/reminders/{rule.id}/actions",
        {"action": "complete"},
    )

    assert response.status_code == 404

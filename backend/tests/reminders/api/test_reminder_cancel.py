from datetime import datetime, timedelta, timezone as datetime_timezone

import pytest
from django.utils import timezone

from apps.reminders.models import ReminderDraft, ReminderRule, VoiceParseSession


NOW = datetime(2026, 8, 5, 4, 0, tzinfo=datetime_timezone.utc)


def create_rule(*, owner, title, scheduled_at):
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
        source_draft=draft,
    )


@pytest.mark.django_db
def test_pending_reminder_can_be_cancelled_idempotently(
    api_client,
    user,
    mocker,
):
    rule = create_rule(
        owner=user,
        title="cancel me",
        scheduled_at=NOW + timedelta(minutes=5),
    )
    now_mock = mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    first = api_client.post(f"/api/v1/reminders/{rule.id}/cancel")
    now_mock.return_value = NOW + timedelta(minutes=1)
    second = api_client.post(f"/api/v1/reminders/{rule.id}/cancel")

    assert first.status_code == second.status_code == 200
    assert first.json()["status"] == second.json()["status"] == "cancelled"
    assert first.json()["cancelled_at"] == second.json()["cancelled_at"]
    rule.refresh_from_db()
    assert rule.enabled is False
    assert rule.cancelled_at == NOW


@pytest.mark.django_db
def test_expired_reminder_cannot_be_cancelled(api_client, user, mocker):
    rule = create_rule(owner=user, title="too late", scheduled_at=NOW)
    mocker.patch("apps.reminders.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.post(f"/api/v1/reminders/{rule.id}/cancel")

    assert response.status_code == 409
    assert response.json() == {
        "code": "reminder_expired",
        "detail": "提醒时间已过，不能取消",
    }
    rule.refresh_from_db()
    assert rule.enabled is True
    assert rule.cancelled_at is None


@pytest.mark.django_db
def test_cancel_returns_404_for_missing_or_other_owner(
    api_client,
    user,
    django_user_model,
):
    other = django_user_model.objects.create_user(username="cancel-owner")
    rule = create_rule(
        owner=other,
        title="private reminder",
        scheduled_at=NOW + timedelta(minutes=5),
    )
    api_client.force_authenticate(user)

    other_response = api_client.post(f"/api/v1/reminders/{rule.id}/cancel")
    missing_response = api_client.post(
        "/api/v1/reminders/00000000-0000-0000-0000-000000000000/cancel"
    )

    assert other_response.status_code == 404
    assert missing_response.status_code == 404

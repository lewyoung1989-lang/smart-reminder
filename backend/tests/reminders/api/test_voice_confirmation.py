from datetime import timedelta

import pytest
from django.utils import timezone

from apps.reminders.models import ReminderDraft, VoiceParseSession


def _create_draft(user, *, ambiguities=None):
    expires_at = timezone.now() + timedelta(minutes=15)
    session = VoiceParseSession.objects.create(
        user=user,
        transcript_sha256="0" * 64,
        expires_at=expires_at,
    )
    draft_json = {
        "intent": "create_reminder",
        "title": "起床并查看天气",
        "schedule": {
            "type": "once",
            "local_datetime": "2026-08-04T07:30:00+08:00",
            "timezone": "Asia/Shanghai",
        },
        "precheck": {
            "minutes_before": 20,
            "condition": {
                "type": "precipitation_probability",
                "window_minutes": 120,
                "operator": ">=",
                "value": 40,
            },
        },
        "severity": "alarm",
        "condition_met_message": "未来两小时可能有雨，建议带伞",
        "ambiguities": ambiguities or [],
    }
    return ReminderDraft.objects.create(
        session=session,
        draft_json=draft_json,
        ambiguities_json=ambiguities or [],
        expires_at=expires_at,
    )


@pytest.mark.django_db
def test_confirmation_creates_one_reminder_rule(api_client, user):
    draft = _create_draft(user)
    api_client.force_authenticate(user)

    first = api_client.post(f"/api/v1/voice/reminder-drafts/{draft.id}/confirm")
    second = api_client.post(f"/api/v1/voice/reminder-drafts/{draft.id}/confirm")

    from apps.reminders.models import ReminderRule

    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json()["reminder_id"] == second.json()["reminder_id"]
    assert ReminderRule.objects.filter(owner=user).count() == 1


@pytest.mark.django_db
def test_ambiguous_draft_cannot_be_confirmed(api_client, user):
    draft = _create_draft(user, ambiguities=["缺少提醒时间"])
    api_client.force_authenticate(user)

    response = api_client.post(f"/api/v1/voice/reminder-drafts/{draft.id}/confirm")

    assert response.status_code == 409
    assert response.json()["code"] == "draft_has_ambiguities"


@pytest.mark.django_db
def test_user_cannot_confirm_another_users_draft(api_client, user, django_user_model):
    owner = django_user_model.objects.create_user(username="draft-owner")
    draft = _create_draft(owner)
    api_client.force_authenticate(user)

    response = api_client.post(f"/api/v1/voice/reminder-drafts/{draft.id}/confirm")

    assert response.status_code == 404
    assert response.json()["detail"] == "未找到该语音草稿"

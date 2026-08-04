import pytest

from apps.reminders.models import ReminderDraft, ReminderRule, VoiceParseSession


@pytest.mark.django_db
def test_authenticated_user_creates_text_reminder_draft(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/reminder-drafts",
        {"text": "1分钟后提醒我喝水"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["status"] == "pending_confirmation"
    assert payload["parser_source"] == "local"
    assert payload["draft"]["title"] == "喝水"
    assert payload["draft"]["ambiguities"] == []
    assert ReminderDraft.objects.count() == 1
    assert ReminderRule.objects.count() == 0
    assert VoiceParseSession.objects.get().parser_source == "local"


@pytest.mark.django_db
def test_text_draft_requires_non_blank_text(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/reminder-drafts",
        {"text": "  "},
        format="json",
    )

    assert response.status_code == 400
    assert "text" in response.json()


@pytest.mark.django_db
def test_anonymous_user_cannot_create_text_draft(api_client):
    response = api_client.post(
        "/api/v1/reminder-drafts",
        {"text": "1分钟后提醒我喝水"},
        format="json",
    )

    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


@pytest.mark.django_db
def test_text_draft_can_be_confirmed_idempotently(api_client, user):
    api_client.force_authenticate(user)
    created = api_client.post(
        "/api/v1/reminder-drafts",
        {"text": "1分钟后提醒我喝水"},
        format="json",
    ).json()

    first = api_client.post(f"/api/v1/reminder-drafts/{created['id']}/confirm")
    second = api_client.post(f"/api/v1/reminder-drafts/{created['id']}/confirm")

    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json()["reminder_id"] == second.json()["reminder_id"]
    assert ReminderRule.objects.count() == 1


@pytest.mark.django_db
def test_legacy_voice_path_still_accepts_transcript(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/voice/reminder-drafts",
        {"transcript": "1分钟后提醒我喝水"},
        format="json",
    )

    assert response.status_code == 201
    assert response.json()["draft"]["title"] == "喝水"

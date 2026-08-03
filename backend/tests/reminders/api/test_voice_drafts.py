import hashlib

import pytest


TRANSCRIPT = "明天早上七点半叫我起床，先查未来两小时天气，如果下雨提醒我带伞。"


@pytest.mark.django_db
def test_authenticated_user_creates_reviewable_voice_draft(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/voice/reminder-drafts",
        {"transcript": TRANSCRIPT},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["status"] == "pending_confirmation"
    assert payload["draft"]["severity"] == "alarm"
    assert payload["draft"]["ambiguities"] == []


@pytest.mark.django_db
def test_voice_draft_stores_hash_instead_of_raw_transcript(api_client, user):
    from apps.reminders.models import VoiceParseSession

    api_client.force_authenticate(user)
    api_client.post(
        "/api/v1/voice/reminder-drafts",
        {"transcript": TRANSCRIPT},
        format="json",
    )

    session = VoiceParseSession.objects.get()
    assert session.transcript_sha256 == hashlib.sha256(TRANSCRIPT.encode()).hexdigest()
    assert not hasattr(session, "transcript")


@pytest.mark.django_db
def test_anonymous_user_cannot_create_voice_draft(api_client):
    response = api_client.post(
        "/api/v1/voice/reminder-drafts",
        {"transcript": TRANSCRIPT},
        format="json",
    )

    assert response.status_code == 403

from datetime import timedelta

import pytest
from django.utils import timezone

from apps.workflows.models import WorkflowDraft


CREATE_URL = "/api/v1/workflow-drafts"
CLARIFICATION_TEXT = "以后每天9点我吃药"


def create_clarification_draft(api_client, text=CLARIFICATION_TEXT):
    response = api_client.post(CREATE_URL, {"text": text}, format="json")
    assert response.status_code == 201
    body = response.json()
    assert body["policy"]["decision"] == "needs_clarification"
    return body


@pytest.mark.django_db
def test_answer_requires_authentication(api_client):
    response = api_client.post(
        f"{CREATE_URL}/00000000-0000-0000-0000-000000000000/answers",
        {"answer": "吃阿莫西林1片"},
        format="json",
    )

    assert response.status_code == 401


@pytest.mark.django_db
def test_answer_accepts_only_the_answer_field(api_client, user):
    api_client.force_authenticate(user)
    created = create_clarification_draft(api_client)

    response = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "吃阿莫西林1片", "trusted": True},
        format="json",
    )

    assert response.status_code == 400
    assert "trusted" in response.json()


@pytest.mark.django_db
def test_resolving_answer_makes_the_draft_confirmable(api_client, user):
    api_client.force_authenticate(user)
    created = create_clarification_draft(api_client)

    response = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "吃阿莫西林1片"},
        format="json",
    )

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == created["id"]
    assert body["task"]["ambiguities"] == []
    assert body["task"]["slots"]["medicine_name"] == "阿莫西林"
    assert body["task"]["slots"]["frequency"] == "daily"
    assert body["task"]["slots"]["time_of_day"] == "09:00"
    assert body["workflow"]["template_key"] == "medication_cycle"
    assert body["policy"]["decision"] == "needs_confirmation"

    confirmed = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")
    assert confirmed.status_code == 201


@pytest.mark.django_db
def test_partial_answer_keeps_clarifying_with_parsed_slots(api_client, user):
    api_client.force_authenticate(user)
    created = create_clarification_draft(api_client)

    response = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "1片"},
        format="json",
    )

    assert response.status_code == 200
    body = response.json()
    assert body["policy"]["decision"] == "needs_clarification"
    assert body["policy"]["question"] == "请补充药品名称"
    assert body["task"]["slots"]["dose_text"] == "1片"
    assert body["task"]["slots"]["time_of_day"] == "09:00"
    draft = WorkflowDraft.objects.get(id=created["id"])
    assert draft.clarification_rounds == 1

    resolved = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "吃阿莫西林"},
        format="json",
    )
    assert resolved.status_code == 200
    assert resolved.json()["policy"]["decision"] == "needs_confirmation"


@pytest.mark.django_db
def test_three_clarification_rounds_are_the_maximum(api_client, user):
    api_client.force_authenticate(user)
    created = create_clarification_draft(api_client)

    first = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "1片"},
        format="json",
    )
    second = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "长期服用"},
        format="json",
    )
    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["policy"]["decision"] == "needs_clarification"

    third = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "每天"},
        format="json",
    )
    assert third.status_code == 409
    assert third.json()["code"] == "workflow_clarification_exhausted"


@pytest.mark.django_db
def test_answer_for_missing_draft_returns_404(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        f"{CREATE_URL}/00000000-0000-0000-0000-000000000000/answers",
        {"answer": "吃阿莫西林1片"},
        format="json",
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_answer_for_expired_draft_returns_410(api_client, user):
    api_client.force_authenticate(user)
    created = create_clarification_draft(api_client)
    WorkflowDraft.objects.filter(id=created["id"]).update(
        expires_at=timezone.now() - timedelta(minutes=1)
    )

    response = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "吃阿莫西林1片"},
        format="json",
    )

    assert response.status_code == 410
    assert response.json()["code"] == "workflow_draft_expired"


@pytest.mark.django_db
def test_answer_for_confirmed_draft_returns_409(api_client, user):
    api_client.force_authenticate(user)
    created = create_clarification_draft(api_client)
    api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "吃阿莫西林1片"},
        format="json",
    )
    confirmed = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")
    assert confirmed.status_code == 201

    response = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "改成2片"},
        format="json",
    )

    assert response.status_code == 409
    assert response.json()["code"] == "workflow_draft_confirmed"


@pytest.mark.django_db
def test_quick_create_routed_draft_keeps_source_text_for_answers(api_client, user):
    api_client.force_authenticate(user)

    created = api_client.post(
        "/api/v1/reminder-drafts",
        {"text": CLARIFICATION_TEXT},
        format="json",
    ).json()
    assert created["draft_type"] == "workflow"

    response = api_client.post(
        f"{CREATE_URL}/{created['id']}/answers",
        {"answer": "吃阿莫西林1片"},
        format="json",
    )

    assert response.status_code == 200
    assert response.json()["policy"]["decision"] == "needs_confirmation"

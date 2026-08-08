from datetime import datetime, timedelta, timezone as datetime_timezone

import pytest
from django.utils import timezone

from apps.reminders.models import ReminderRule
from apps.workflows.models import TrustGrant, WorkflowDraft, WorkflowRun


CREATE_URL = "/api/v1/workflow-drafts"
COMPLETE_TEXT = "明天八点到虹桥火车站，坐公交出门"
NOW = datetime(2026, 8, 8, 9, 30, tzinfo=datetime_timezone.utc)


def create_draft(api_client, text=COMPLETE_TEXT):
    return api_client.post(CREATE_URL, {"text": text}, format="json")


@pytest.mark.django_db
def test_workflow_draft_requires_authentication(api_client):
    response = create_draft(api_client)

    assert response.status_code == 401


@pytest.mark.django_db
def test_workflow_draft_accepts_only_a_text_field(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": COMPLETE_TEXT, "trusted": True},
        format="json",
    )

    assert response.status_code == 400
    assert "trusted" in response.json()


@pytest.mark.django_db
def test_workflow_draft_returns_and_persists_compiled_specs(api_client, user):
    api_client.force_authenticate(user)

    response = create_draft(api_client)

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "pending_confirmation"
    assert body["task"]["intent"] == "create_workflow"
    assert body["workflow"]["template_key"] == "smart_departure"
    assert body["policy"]["decision"] == "needs_confirmation"
    draft = WorkflowDraft.objects.get(id=body["id"])
    assert draft.user == user
    assert draft.task_spec_json == body["task"]
    assert draft.workflow_spec_json == body["workflow"]
    assert draft.policy_json == body["policy"]
    assert draft.expires_at - draft.created_at <= timedelta(minutes=31)


@pytest.mark.django_db
def test_confirmation_creates_a_workflow_backed_reminder_idempotently(api_client, user):
    api_client.force_authenticate(user)
    created = create_draft(api_client).json()

    first = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")
    second = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")

    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json()["reminder_id"] == second.json()["reminder_id"]
    rule = ReminderRule.objects.get(id=first.json()["reminder_id"])
    assert str(rule.workflow_draft_id) == created["id"]
    assert rule.source_draft is None
    assert rule.schedule_json == {}
    assert rule.scheduled_at is None
    assert rule.workflow_spec_json == created["workflow"]
    assert rule.severity == "notification"
    assert WorkflowDraft.objects.get(id=created["id"]).status == "confirmed"
    assert (
        TrustGrant.objects.filter(user=user, status=TrustGrant.Status.ACTIVE).count()
        == 1
    )


@pytest.mark.django_db
def test_smart_departure_confirmation_is_due_and_dispatches(
    api_client, user, mocker, django_capture_on_commit_callbacks
):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    mocker.patch("apps.workflows.api.views.timezone.now", return_value=NOW)
    enqueue = mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")
    api_client.force_authenticate(user)
    created = create_draft(api_client).json()

    confirmed = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")

    assert confirmed.status_code == 201
    rule = ReminderRule.objects.get(id=confirmed.json()["reminder_id"])
    arrival = next(
        node["config"]["arrival_time"]
        for node in created["workflow"]["nodes"]
        if node["id"] == "before-arrival"
    )
    assert rule.next_run_at == datetime.fromisoformat(arrival) - timedelta(hours=2)

    with django_capture_on_commit_callbacks(execute=True):
        dispatch_due_workflows(rule.next_run_at, batch_size=10)

    assert WorkflowRun.objects.filter(workflow=rule).count() == 1
    rule.refresh_from_db()
    assert rule.next_run_at == datetime.fromisoformat(arrival) - timedelta(minutes=20)
    enqueue.assert_called_once()


@pytest.mark.django_db
@pytest.mark.parametrize(
    "text, template_key",
    [
        ("每天早上八点吃阿莫西林 0.5g", "medication_cycle"),
        ("药品 med-1 有效期提前30天提醒", "medicine_expiry"),
    ],
)
def test_medication_and_expiry_confirmations_get_template_schedule(
    api_client, user, mocker, text, template_key
):
    mocker.patch("apps.workflows.api.views.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)
    created = create_draft(api_client, text).json()

    confirmed = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")

    assert confirmed.status_code == 201
    rule = ReminderRule.objects.get(id=confirmed.json()["reminder_id"])
    assert rule.template_key == template_key
    if template_key == "medication_cycle":
        assert rule.next_run_at == datetime.fromisoformat("2026-08-09T08:00:00+08:00")
    else:
        assert rule.next_run_at == NOW


@pytest.mark.django_db
def test_legacy_reminder_api_hides_and_refuses_workflow_rules(api_client, user):
    api_client.force_authenticate(user)
    created = create_draft(api_client).json()
    confirmed = api_client.post(f"{CREATE_URL}/{created['id']}/confirm").json()

    listed = api_client.get("/api/v1/reminders")
    cancelled = api_client.post(f"/api/v1/reminders/{confirmed['reminder_id']}/cancel")

    assert listed.status_code == 200
    assert listed.json()["results"] == []
    assert cancelled.status_code == 409
    assert cancelled.json()["code"] == "workflow_requires_workflow_api"


@pytest.mark.django_db
def test_workflow_confirmation_rejects_request_fields(api_client, user):
    api_client.force_authenticate(user)
    created = create_draft(api_client).json()

    response = api_client.post(
        f"{CREATE_URL}/{created['id']}/confirm",
        {"trusted": True},
        format="json",
    )

    assert response.status_code == 400
    assert "trusted" in response.json()


@pytest.mark.django_db
def test_confirmation_rejects_a_clarification_draft(api_client, user):
    api_client.force_authenticate(user)
    created = create_draft(api_client, "帮我安排一下").json()

    response = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")

    assert response.status_code == 409
    assert response.json()["code"] == "workflow_needs_clarification"
    assert ReminderRule.objects.count() == 0


@pytest.mark.django_db
def test_r2_confirmation_does_not_create_a_trust_grant(api_client, user):
    api_client.force_authenticate(user)
    created = create_draft(api_client, "每天早上八点吃阿莫西林 0.5g").json()

    response = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")

    assert response.status_code == 201
    assert TrustGrant.objects.filter(user=user).count() == 0


@pytest.mark.django_db
def test_confirmation_rejects_an_expired_draft(api_client, user):
    api_client.force_authenticate(user)
    created = create_draft(api_client).json()
    WorkflowDraft.objects.filter(id=created["id"]).update(
        expires_at=timezone.now() - timedelta(seconds=1)
    )

    response = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")

    assert response.status_code == 410
    assert response.json()["code"] == "workflow_draft_expired"


@pytest.mark.django_db
def test_user_cannot_confirm_another_users_workflow_draft(
    api_client, user, django_user_model
):
    owner = django_user_model.objects.create_user(
        username="workflow-owner", password="test-password"
    )
    api_client.force_authenticate(owner)
    created = create_draft(api_client).json()
    api_client.force_authenticate(user)

    response = api_client.post(f"{CREATE_URL}/{created['id']}/confirm")

    assert response.status_code == 404

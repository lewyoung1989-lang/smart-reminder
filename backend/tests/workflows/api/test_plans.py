from datetime import datetime, timezone as datetime_timezone

import pytest

from apps.reminders.models import ReminderRule
from apps.workflows.domain.schemas import TaskSpec
from apps.workflows.models import WorkflowDraft, WorkflowRun
from apps.workflows.services.compiler import WorkflowCompiler


NOW = datetime(2026, 8, 11, 10, 0, tzinfo=datetime_timezone.utc)


def create_workflow_draft(user, *, medicine_name="布洛芬", dose_text="1片"):
    return WorkflowDraft.objects.create(
        user=user,
        source_text="我每天晚上8点吃布洛芬",
        task_spec_json={
            "schema_version": 1,
            "intent": "create_workflow",
            "template_hint": "medication_cycle",
            "title": "用药提醒",
            "slots": {
                "medicine_name": medicine_name,
                "dose_text": dose_text,
                "frequency": "daily",
                "time_of_day": "20:00",
            },
            "requested_capabilities": ["medicine.schedule", "notification.important"],
            "ambiguities": [],
        },
        workflow_spec_json={"template_key": "medication_cycle"},
        policy_json={"decision": "needs_confirmation"},
        status=WorkflowDraft.Status.CONFIRMED,
        expires_at=NOW,
        confirmed_at=NOW,
    )


def create_plan(user, **overrides):
    workflow_spec = WorkflowCompiler().compile(
        TaskSpec(
            template_hint="medication_cycle",
            title="用药提醒",
            slots={
                "medicine_name": "布洛芬",
                "dose_text": "1片",
                "frequency": "daily",
                "time_of_day": "20:00",
            },
            requested_capabilities=[
                "medicine.schedule",
                "notification.important",
            ],
        )
    )
    values = {
        "owner": user,
        "title": "用药提醒",
        "timezone": "Asia/Shanghai",
        "schedule_json": {},
        "conditions_json": {},
        "severity": "notification",
        "template_key": "medication_cycle",
        "template_version": "1.0.0",
        "schema_version": 1,
        "workflow_spec_json": workflow_spec.model_dump(mode="json"),
        "next_run_at": NOW,
        "workflow_draft": create_workflow_draft(user),
    }
    values.update(overrides)
    return ReminderRule.objects.create(**values)


@pytest.mark.django_db
def test_plan_list_requires_authentication(api_client):
    response = api_client.get("/api/v1/plans")

    assert response.status_code == 401


@pytest.mark.django_db
def test_plan_list_returns_workflow_backed_rules_only(api_client, user, django_user_model):
    other = django_user_model.objects.create_user(username="plans-other")
    create_plan(other, title="他人的计划")
    plan = create_plan(user)
    ReminderRule.objects.create(
        owner=user,
        title="一次性提醒",
        timezone="Asia/Shanghai",
        schedule_json={},
        conditions_json={},
        severity="notification",
        scheduled_at=NOW,
    )
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/plans")

    assert response.status_code == 200
    body = response.json()
    assert body["is_offline"] is False
    assert body["results"] == [
        {
            "id": str(plan.id),
            "title": "用药提醒",
            "subtitle": "布洛芬 · 1片",
            "next_run_at": "2026-08-11T10:00:00+00:00",
            "status": "active",
            "kind": "medication",
        }
    ]


@pytest.mark.django_db
def test_plan_detail_returns_business_fields(api_client, user):
    plan = create_plan(user)
    api_client.force_authenticate(user)

    response = api_client.get(f"/api/v1/plans/{plan.id}")

    assert response.status_code == 200
    body = response.json()
    assert body["summary"]["id"] == str(plan.id)
    assert body["summary"]["subtitle"] == "布洛芬 · 1片"
    assert body["reminder_label"] == "每天 20:00 通知提醒"
    assert body["queried_sources"] == []
    assert body["executions"] == []
    assert body["notification_schedule"] == {
        "scheduled_at": "2026-08-11T10:00:00+00:00",
        "repeat": "daily",
        "title": "用药提醒",
        "timezone": "Asia/Shanghai",
    }


@pytest.mark.django_db
def test_plan_detail_is_owner_scoped(api_client, user, django_user_model):
    other = django_user_model.objects.create_user(username="plans-owner")
    plan = create_plan(other)
    api_client.force_authenticate(user)

    response = api_client.get(f"/api/v1/plans/{plan.id}")

    assert response.status_code == 404


@pytest.mark.django_db
def test_plan_detail_preserves_non_terminal_execution_status(api_client, user):
    plan = create_plan(user)
    run = WorkflowRun.objects.create(
        workflow=plan,
        idempotency_key="plan-detail-pending",
        status=WorkflowRun.Status.PENDING,
        scheduled_for=NOW,
    )
    api_client.force_authenticate(user)

    response = api_client.get(f"/api/v1/plans/{plan.id}")

    assert response.status_code == 200
    assert response.json()["executions"] == [
        {
            "started_at": run.scheduled_for.isoformat(),
            "status": "pending",
            "message": "等待执行",
        }
    ]
    assert response.json()["is_degraded"] is False


@pytest.mark.django_db
def test_plan_can_be_paused_resumed_and_soft_deleted(api_client, user):
    plan = create_plan(user)
    api_client.force_authenticate(user)

    paused = api_client.post(f"/api/v1/plans/{plan.id}/pause")
    assert paused.status_code == 200
    assert paused.json()["summary"]["status"] == "paused"
    plan.refresh_from_db()
    assert plan.enabled is False
    assert plan.paused_reason == "user_paused"

    resumed = api_client.post(f"/api/v1/plans/{plan.id}/resume")
    assert resumed.status_code == 200
    assert resumed.json()["summary"]["status"] == "active"
    plan.refresh_from_db()
    assert plan.enabled is True
    assert plan.paused_reason is None

    deleted = api_client.delete(f"/api/v1/plans/{plan.id}")
    assert deleted.status_code == 204
    plan.refresh_from_db()
    assert plan.cancelled_at is not None
    assert plan.enabled is False
    assert ReminderRule.objects.filter(id=plan.id).exists()
    assert api_client.get("/api/v1/plans").json()["results"] == []


@pytest.mark.django_db
def test_plan_mutations_are_owner_scoped(api_client, user, django_user_model):
    other = django_user_model.objects.create_user(username="plans-mutation-owner")
    plan = create_plan(other)
    api_client.force_authenticate(user)

    assert api_client.post(f"/api/v1/plans/{plan.id}/pause").status_code == 404
    assert api_client.post(f"/api/v1/plans/{plan.id}/resume").status_code == 404
    assert api_client.delete(f"/api/v1/plans/{plan.id}").status_code == 404

from datetime import datetime, timedelta, timezone as datetime_timezone

import pytest

from apps.reminders.models import ReminderRule
from apps.medication.models import MedicationOccurrence, MedicationPlan
from apps.medicines.models import MedicineItem
from apps.workflows.models import NotificationOutbox, WorkflowRun


NOW = datetime(2026, 8, 8, 1, 0, tzinfo=datetime_timezone.utc)


def create_workflow_rule(owner, *, title, **overrides):
    values = {
        "owner": owner,
        "title": title,
        "timezone": "Asia/Shanghai",
        "schedule_json": {},
        "conditions_json": {},
        "severity": "notification",
        "template_key": "medication_cycle",
        "template_version": "1.0.0",
        "schema_version": 1,
        "workflow_spec_json": {"nodes": [{"provider_secret": "hidden"}]},
    }
    values.update(overrides)
    return ReminderRule.objects.create(**values)


def create_outbox(owner, *, title, suffix, **overrides):
    rule = create_workflow_rule(owner, title=title)
    run = WorkflowRun.objects.create(
        workflow=rule,
        idempotency_key=f"run-{suffix}",
        result_json={"provider_secret": "hidden"},
    )
    values = {
        "workflow_run": run,
        "node_id": "notify",
        "kind": "notification",
        "payload_json": {"provider_secret": "hidden"},
        "idempotency_key": f"outbox-{suffix}",
    }
    values.update(overrides)
    return NotificationOutbox.objects.create(**values)


@pytest.mark.django_db
def test_today_requires_authentication(api_client):
    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


@pytest.mark.django_db
def test_today_is_owner_scoped_and_exposes_only_business_fields(
    api_client, user, django_user_model, mocker
):
    other = django_user_model.objects.create_user(username="action-center-other")
    create_outbox(
        other,
        title="other failed",
        suffix="other",
        status=NotificationOutbox.Status.FAILED,
        last_error="private transport detail",
    )
    create_outbox(
        user,
        title="my failed",
        suffix="mine",
        status=NotificationOutbox.Status.FAILED,
        last_error="private transport detail",
    )
    create_workflow_rule(
        other,
        title="other paused",
        enabled=False,
        paused_reason="private",
    )
    create_workflow_rule(
        other,
        title="other scheduled",
        next_run_at=NOW + timedelta(hours=1),
    )
    create_outbox(
        other,
        title="other retry",
        suffix="other-retry",
        status=NotificationOutbox.Status.PENDING,
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    item = response.json()["need_decision"]["results"][0]
    assert item["title"] == "my failed"
    assert item["status"] == "failed"
    assert set(item) == {"id", "title", "kind", "status", "occurred_at"}
    assert all(
        item["title"] not in {"other failed", "other paused", "other scheduled", "other retry"}
        for queue in response.json().values()
        for item in queue["results"]
    )


@pytest.mark.django_db
def test_today_separates_actionable_statuses_and_orders_each_queue(
    api_client, user, mocker
):
    create_outbox(
        user,
        title="failed earlier",
        suffix="failed-earlier",
        status=NotificationOutbox.Status.FAILED,
    )
    failed_later = create_outbox(
        user,
        title="failed later",
        suffix="failed-later",
        status=NotificationOutbox.Status.FAILED,
    )
    NotificationOutbox.objects.filter(id=failed_later.id).update(
        created_at=NOW - timedelta(minutes=5)
    )
    paused = create_workflow_rule(
        user,
        title="paused rule",
        enabled=False,
        paused_reason="needs confirmation",
        next_run_at=NOW + timedelta(hours=3),
    )
    scheduled_later = create_workflow_rule(
        user, title="scheduled later", next_run_at=NOW + timedelta(hours=2)
    )
    scheduled_next = create_workflow_rule(
        user, title="scheduled next", next_run_at=NOW + timedelta(hours=1)
    )
    due = create_outbox(
        user,
        title="retry due",
        suffix="due",
        status=NotificationOutbox.Status.PENDING,
        next_attempt_at=NOW - timedelta(minutes=1),
    )
    create_outbox(
        user,
        title="retry later",
        suffix="later",
        status=NotificationOutbox.Status.PENDING,
        next_attempt_at=NOW + timedelta(minutes=1),
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    body = response.json()
    assert [item["status"] for item in body["need_decision"]["results"]] == [
        "failed",
        "failed",
        "paused",
    ]
    assert [item["title"] for item in body["upcoming"]["results"]] == [
        "retry due",
        "scheduled next",
        "scheduled later",
    ]
    assert body["upcoming"]["results"][0]["id"] == str(due.id)
    assert all("+08:00" in item["occurred_at"] for item in body["need_decision"]["results"])
    assert body["upcoming"]["results"][1]["id"] == str(scheduled_next.id)
    assert body["upcoming"]["results"][2]["id"] == str(scheduled_later.id)
    assert body["need_decision"]["results"][-1]["id"] == str(paused.id)


@pytest.mark.django_db
def test_today_returns_empty_paginated_queues(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert response.json() == {
        "need_decision": {"next": None, "results": []},
        "upcoming": {"next": None, "results": []},
    }


@pytest.mark.django_db
def test_today_includes_paused_rules_without_a_next_run(api_client, user, mocker):
    paused = create_workflow_rule(
        user,
        title="paused without next run",
        enabled=False,
        paused_reason="needs review",
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert response.json()["need_decision"]["results"] == [
        {
            "id": str(paused.id),
            "title": "paused without next run",
            "kind": "workflow",
            "status": "paused",
            "occurred_at": None,
        }
    ]


@pytest.mark.django_db
def test_today_includes_immediately_due_pending_outbox(api_client, user, mocker):
    outbox = create_outbox(
        user,
        title="retry now",
        suffix="retry-now",
        status=NotificationOutbox.Status.PENDING,
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert response.json()["upcoming"]["results"][0]["id"] == str(outbox.id)
    assert response.json()["upcoming"]["results"][0]["occurred_at"] is None


@pytest.mark.django_db
def test_today_uses_validated_bounded_pagination(api_client, user, mocker):
    for index in range(3):
        create_workflow_rule(
            user,
            title=f"scheduled {index}",
            next_run_at=NOW + timedelta(hours=index + 1),
        )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get(
        "/api/v1/action-center/today", {"offset": 1, "limit": 1}
    )

    assert response.status_code == 200
    upcoming = response.json()["upcoming"]
    assert [item["title"] for item in upcoming["results"]] == ["scheduled 1"]
    assert "offset=2" in upcoming["next"]
    assert "limit=1" in upcoming["next"]

    for offset in ("-1", "invalid"):
        invalid = api_client.get(
            "/api/v1/action-center/today", {"offset": offset}
        )
        assert invalid.status_code == 400

    too_large = api_client.get("/api/v1/action-center/today", {"limit": 51})
    assert too_large.status_code == 400


@pytest.mark.django_db
def test_today_includes_due_and_upcoming_medication_occurrences(api_client, user, mocker):
    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    due = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=NOW - timedelta(minutes=5),
        index=1,
        idempotency_key="due-medication",
    )
    upcoming = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=NOW + timedelta(hours=1),
        index=2,
        idempotency_key="upcoming-medication",
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert {
        "id": str(due.id),
        "title": "服用布洛芬（一次一片）",
        "kind": "medication",
        "status": "due",
        "occurred_at": "2026-08-08T08:55:00+08:00",
    } in response.json()["need_decision"]["results"]
    assert {
        "id": str(upcoming.id),
        "title": "服用布洛芬（一次一片）",
        "kind": "medication",
        "status": "scheduled",
        "occurred_at": "2026-08-08T10:00:00+08:00",
    } in response.json()["upcoming"]["results"]

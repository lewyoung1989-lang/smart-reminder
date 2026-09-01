from datetime import datetime, timedelta, timezone as datetime_timezone

import pytest

from apps.reminders.models import ReminderRule
from apps.medication.models import MedicationOccurrence, MedicationPlan
from apps.medicines.models import (
    ExpiryAlertState,
    InventoryBatch,
    LowStockAlertState,
    MedicineItem,
)
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


def create_ordinary_reminder(owner, *, title, scheduled_at, **overrides):
    values = {
        "owner": owner,
        "title": title,
        "timezone": "Asia/Shanghai",
        "schedule_json": {"local_datetime": scheduled_at.isoformat()},
        "conditions_json": {},
        "severity": "notification",
        "scheduled_at": scheduled_at,
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
    assert set(item) == {
        "id",
        "title",
        "kind",
        "status",
        "occurred_at",
        "action_target",
    }
    assert item["action_target"] == {
        "resource": "notification_outbox",
        "id": item["id"],
    }
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
        user,
        title="scheduled later",
        template_key="smart_departure",
        next_run_at=NOW + timedelta(hours=2),
    )
    scheduled_next = create_workflow_rule(
        user,
        title="scheduled next",
        template_key="smart_departure",
        next_run_at=NOW + timedelta(hours=1),
    )
    create_workflow_rule(
        user,
        title="scheduled tomorrow",
        template_key="smart_departure",
        next_run_at=NOW + timedelta(days=1),
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
    assert body["upcoming"]["results"][1]["subtitle"] == "路线与天气提醒"
    assert body["upcoming"]["results"][1]["action_target"] == {
        "resource": "workflow",
        "id": str(scheduled_next.id),
    }
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
def test_today_includes_active_expiry_alerts_only_for_the_owner(api_client, user, django_user_model):
    medicine = MedicineItem.objects.create(owner=user, name="滴眼液")
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date=NOW.date(),
    )
    alert = ExpiryAlertState.objects.create(
        batch=batch,
        threshold_days=0,
        deadline=NOW.date(),
        status=ExpiryAlertState.Status.ACTIVE,
    )
    other = django_user_model.objects.create_user(username="expiry-other")
    other_medicine = MedicineItem.objects.create(owner=other, name="他人的药")
    other_batch = InventoryBatch.objects.create(
        medicine=other_medicine,
        expiry_date=NOW.date(),
    )
    ExpiryAlertState.objects.create(
        batch=other_batch,
        threshold_days=0,
        deadline=NOW.date(),
        status=ExpiryAlertState.Status.ACTIVE,
    )
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert response.json()["need_decision"]["results"] == [
        {
            "id": str(alert.id),
            "title": "滴眼液已到期，请确认是否已处理",
            "kind": "medicine_expiry",
            "status": "expired",
            "occurred_at": "2026-08-08",
            "action_target": {
                "resource": "inventory_batch",
                "id": str(batch.id),
            },
        }
    ]


@pytest.mark.django_db
def test_today_includes_active_low_stock_alerts_only_for_accessible_medicines(
    api_client, user, django_user_model, mocker
):
    medicine = MedicineItem.objects.create(owner=user, name="拜新同")
    alert = LowStockAlertState.objects.create(
        medicine=medicine,
        unit_name="片",
        threshold_days=3,
        remaining_quantity="2",
        daily_quantity="1",
        days_remaining="2.00",
        status=LowStockAlertState.Status.ACTIVE,
        activated_at=NOW,
    )
    other = django_user_model.objects.create_user(username="low-stock-other")
    other_medicine = MedicineItem.objects.create(owner=other, name="他人的药")
    LowStockAlertState.objects.create(
        medicine=other_medicine,
        unit_name="片",
        threshold_days=3,
        remaining_quantity="1",
        daily_quantity="1",
        days_remaining="1.00",
        status=LowStockAlertState.Status.ACTIVE,
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert response.json()["need_decision"]["results"] == [
        {
            "id": str(alert.id),
            "title": "拜新同余量不足，还能用约2天（剩余2片）",
            "kind": "medicine_low_stock",
            "status": "low_stock",
            "occurred_at": "2026-08-08T09:00:00+08:00",
            "action_target": {
                "resource": "low_stock_alert",
                "id": str(alert.id),
            },
        }
    ]


@pytest.mark.django_db
def test_low_stock_alert_action_marks_alert_resolved(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="拜新同")
    alert = LowStockAlertState.objects.create(
        medicine=medicine,
        unit_name="片",
        threshold_days=3,
        remaining_quantity="2",
        daily_quantity="1",
        days_remaining="2.00",
        status=LowStockAlertState.Status.ACTIVE,
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/low-stock-alerts/{alert.id}/actions",
        {"action": "handled"},
    )

    assert response.status_code == 200
    alert.refresh_from_db()
    assert alert.status == LowStockAlertState.Status.RESOLVED
    assert alert.resolved_at is not None


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
            "action_target": {"resource": "workflow", "id": str(paused.id)},
        }
    ]


@pytest.mark.django_db
def test_today_excludes_user_paused_and_deleted_workflows(api_client, user, mocker):
    create_workflow_rule(
        user,
        title="user paused medication",
        enabled=False,
        paused_reason="user_paused",
        next_run_at=NOW,
    )
    create_workflow_rule(
        user,
        title="deleted medication",
        enabled=False,
        paused_reason="user_deleted",
        cancelled_at=NOW,
        next_run_at=NOW,
    )
    system_paused = create_workflow_rule(
        user,
        title="system paused medication",
        enabled=False,
        paused_reason="medicine_access_lost",
        next_run_at=NOW,
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert response.json()["need_decision"]["results"] == [
        {
            "id": str(system_paused.id),
            "title": "system paused medication",
            "kind": "workflow",
            "status": "paused",
            "occurred_at": "2026-08-08T09:00:00+08:00",
            "action_target": {"resource": "workflow", "id": str(system_paused.id)},
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
            template_key="smart_departure",
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
    parent_rule = create_workflow_rule(
        user,
        title="用药提醒",
        next_run_at=upcoming.scheduled_at,
    )
    MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=NOW + timedelta(days=1),
        index=3,
        idempotency_key="tomorrow-medication",
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
        "action_target": {
            "resource": "medication_occurrence",
            "id": str(due.id),
        },
    } in response.json()["need_decision"]["results"]
    assert {
        "id": str(upcoming.id),
        "title": "服用布洛芬（一次一片）",
        "kind": "medication",
        "status": "scheduled",
        "occurred_at": "2026-08-08T10:00:00+08:00",
    } in response.json()["upcoming"]["results"]
    assert all(
        item["id"] != str(parent_rule.id)
        for item in response.json()["upcoming"]["results"]
    )
    assert all(
        item["occurred_at"] != "2026-08-09T09:00:00+08:00"
        for item in response.json()["upcoming"]["results"]
    )


@pytest.mark.django_db
def test_today_does_not_include_historical_pending_medication_occurrences(
    api_client, user, mocker
):
    medicine = MedicineItem.objects.create(owner=user, name="依巴斯汀")
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    yesterday = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=NOW - timedelta(days=1),
        index=1,
        idempotency_key="yesterday-medication",
    )
    today = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=NOW - timedelta(minutes=10),
        index=2,
        idempotency_key="today-medication",
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    decision_ids = {
        item["id"] for item in response.json()["need_decision"]["results"]
    }
    assert str(today.id) in decision_ids
    assert str(yesterday.id) not in decision_ids


@pytest.mark.django_db
def test_today_includes_due_and_upcoming_ordinary_reminders(
    api_client, user, django_user_model, mocker
):
    due = create_ordinary_reminder(
        user,
        title="给妈妈打电话",
        scheduled_at=NOW - timedelta(minutes=5),
    )
    upcoming = create_ordinary_reminder(
        user,
        title="晚上测血压",
        scheduled_at=NOW + timedelta(hours=1),
    )
    create_ordinary_reminder(
        user,
        title="明天测血压",
        scheduled_at=NOW + timedelta(days=1),
    )
    completed = create_ordinary_reminder(
        user,
        title="已经喝水",
        scheduled_at=NOW - timedelta(hours=1),
        enabled=False,
        completed_at=NOW - timedelta(minutes=10),
    )
    other = django_user_model.objects.create_user(username="ordinary-reminder-other")
    create_ordinary_reminder(
        other,
        title="别人的提醒",
        scheduled_at=NOW + timedelta(hours=2),
    )
    create_ordinary_reminder(
        user,
        title="已取消提醒",
        scheduled_at=NOW + timedelta(hours=3),
        enabled=False,
        cancelled_at=NOW,
    )
    mocker.patch("apps.workflows.api.action.timezone.now", return_value=NOW)
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/action-center/today")

    assert response.status_code == 200
    assert {
        "id": str(due.id),
        "title": "给妈妈打电话",
        "kind": "reminder",
        "status": "due",
        "occurred_at": "2026-08-08T08:55:00+08:00",
        "action_target": {
            "resource": "reminder",
            "id": str(due.id),
            "action": "complete",
        },
        "secondary_action_target": {
            "resource": "reminder",
            "id": str(due.id),
            "action": "snooze",
        },
    } in response.json()["need_decision"]["results"]
    assert {
        "id": str(upcoming.id),
        "title": "晚上测血压",
        "kind": "reminder",
        "status": "scheduled",
        "occurred_at": "2026-08-08T10:00:00+08:00",
    } in response.json()["upcoming"]["results"]
    assert {
        "id": str(completed.id),
        "title": "已经喝水",
        "kind": "reminder",
        "status": "completed",
        "occurred_at": "2026-08-08T08:50:00+08:00",
    } in response.json()["upcoming"]["results"]
    assert all(
        item["title"] not in {"别人的提醒", "已取消提醒", "明天测血压"}
        for queue in response.json().values()
        for item in queue["results"]
    )

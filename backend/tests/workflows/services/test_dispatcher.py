from datetime import date, datetime, timedelta, timezone as datetime_timezone
from zoneinfo import ZoneInfo

import pytest
from django.conf import settings
from django.utils import timezone

from apps.medicines.models import ExpiryAlertState, InventoryBatch, MedicineItem
from apps.reminders.models import ReminderRule
from apps.workflows.domain.schemas import TaskSpec
from apps.workflows.services.compiler import WorkflowCompiler
from apps.workflows.models import NotificationOutbox, WorkflowDraft, WorkflowRun


NOW = datetime(2026, 8, 8, 9, 30, tzinfo=datetime_timezone.utc)


def create_rule(user, *, suffix, next_run_at=NOW, **overrides):
    draft = WorkflowDraft.objects.create(
        user=user,
        task_spec_json={},
        workflow_spec_json={},
        policy_json={},
        expires_at=NOW + timedelta(days=1),
    )
    values = {
        "owner": user,
        "title": f"due workflow {suffix}",
        "timezone": "UTC",
        "schedule_json": {"type": "once"},
        "conditions_json": {},
        "severity": "notification",
        "workflow_draft": draft,
        "next_run_at": next_run_at,
    }
    values.update(overrides)
    return ReminderRule.objects.create(**values)


def create_compiled_rule(user, *, suffix, slots, next_run_at=NOW):
    workflow = WorkflowCompiler().compile(
        TaskSpec(title=f"compiled workflow {suffix}", slots=slots)
    )
    rule = create_rule(user, suffix=suffix, next_run_at=next_run_at)
    rule.workflow_spec_json = workflow.model_dump(mode="json")
    rule.save(update_fields=["workflow_spec_json"])
    return rule


def test_beat_dispatches_due_workflows_every_minute():
    schedule = settings.CELERY_BEAT_SCHEDULE["dispatch-due-workflows-minute"]

    assert schedule == {
        "task": "apps.workflows.tasks.dispatch_due_workflows_task",
        "schedule": 60.0,
    }


def test_beat_publishes_due_outbox_every_minute():
    schedule = settings.CELERY_BEAT_SCHEDULE["publish-due-outbox-minute"]

    assert schedule == {
        "task": "apps.workflows.tasks.publish_due_outbox_task",
        "schedule": 60.0,
    }


@pytest.mark.django_db
def test_dispatcher_creates_run_outbox_and_advances_due_rule(
    user, django_capture_on_commit_callbacks, mocker
):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    rule = create_rule(user, suffix="first")
    enqueue = mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    with django_capture_on_commit_callbacks(execute=True):
        dispatched = dispatch_due_workflows(NOW, batch_size=10)

    run = WorkflowRun.objects.get(workflow=rule)
    outbox = NotificationOutbox.objects.get(workflow_run=run)
    rule.refresh_from_db()
    assert dispatched == [run.id]
    assert run.idempotency_key == f"rule:{rule.id}:{NOW.isoformat()}:scheduled"
    assert run.scheduled_for == NOW
    assert outbox.node_id == "notify"
    assert outbox.idempotency_key == f"run:{run.id}:notify"
    assert rule.next_run_at is None
    enqueue.assert_called_once_with(str(outbox.id))


@pytest.mark.django_db
def test_dispatcher_is_idempotent_for_the_same_scheduled_occurrence(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    rule = create_rule(user, suffix="idempotent")
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(NOW, batch_size=10)
    dispatch_due_workflows(NOW, batch_size=10)

    assert WorkflowRun.objects.filter(workflow=rule).count() == 1
    assert NotificationOutbox.objects.filter(workflow_run__workflow=rule).count() == 1


@pytest.mark.django_db
def test_dispatcher_excludes_cancelled_paused_disabled_and_non_workflow_rules(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    create_rule(user, suffix="eligible")
    create_rule(user, suffix="cancelled", cancelled_at=NOW, enabled=False)
    create_rule(user, suffix="paused", paused_reason="user")
    create_rule(user, suffix="disabled", enabled=False)
    ReminderRule.objects.create(
        owner=user,
        title="ordinary reminder",
        timezone="UTC",
        schedule_json={"type": "once"},
        conditions_json={},
        severity="notification",
        next_run_at=NOW,
    )
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(NOW, batch_size=10)

    assert WorkflowRun.objects.count() == 1
    assert WorkflowRun.objects.get().workflow.title == "due workflow eligible"


@pytest.mark.django_db
def test_dispatcher_locks_the_due_rules_and_obeys_batch_size(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    first = create_rule(user, suffix="first", next_run_at=NOW - timedelta(minutes=2))
    second = create_rule(user, suffix="second", next_run_at=NOW - timedelta(minutes=1))
    locked = mocker.patch.object(
        ReminderRule.objects,
        "select_for_update",
        wraps=ReminderRule.objects.select_for_update,
    )
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(NOW, batch_size=1)

    locked.assert_called_once_with(skip_locked=True)
    assert WorkflowRun.objects.filter(workflow=first).count() == 1
    assert WorkflowRun.objects.filter(workflow=second).count() == 0


@pytest.mark.django_db
def test_dispatcher_rolls_back_rule_when_outbox_creation_fails(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    rule = create_rule(user, suffix="rollback")
    mocker.patch(
        "apps.workflows.services.dispatcher.NotificationOutbox.objects.get_or_create",
        side_effect=RuntimeError("outbox unavailable"),
    )
    enqueue = mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    with pytest.raises(RuntimeError, match="outbox unavailable"):
        dispatch_due_workflows(NOW, batch_size=10)

    rule.refresh_from_db()
    assert rule.next_run_at == NOW
    assert WorkflowRun.objects.filter(workflow=rule).count() == 0
    enqueue.assert_not_called()


@pytest.mark.django_db
def test_daily_medication_workflow_dispatches_consecutive_occurrences(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    rule = create_compiled_rule(
        user,
        suffix="daily-medication",
        slots={
            "medicine_name": "Aspirin",
            "dose_text": "100mg",
            "frequency": "daily",
            "time_of_day": "08:00",
        },
    )
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(NOW, batch_size=10)
    dispatch_due_workflows(NOW + timedelta(days=1), batch_size=10)

    rule.refresh_from_db()
    assert list(
        WorkflowRun.objects.filter(workflow=rule)
        .order_by("scheduled_for")
        .values_list("scheduled_for", flat=True)
    ) == [NOW, NOW + timedelta(days=1)]
    assert rule.next_run_at == NOW + timedelta(days=2)


@pytest.mark.django_db
def test_medicine_expiry_workflow_reads_inventory_deadline_and_creates_outbox(
    user, mocker
):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    medicine = MedicineItem.objects.create(owner=user, name="滴眼液")
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date=NOW.date() + timedelta(days=30),
    )
    rule = create_compiled_rule(
        user,
        suffix="daily-expiry",
        slots={"medicine_id": str(medicine.id), "threshold_days": 30},
    )
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(NOW, batch_size=10)

    run = WorkflowRun.objects.get(workflow=rule)
    outbox = NotificationOutbox.objects.get(workflow_run=run)
    rule.refresh_from_db()
    alert = ExpiryAlertState.objects.get(batch=batch, threshold_days=30)
    assert alert.status == ExpiryAlertState.Status.ACTIVE
    assert alert.threshold_days == 30
    assert run.idempotency_key == (
        f"rule:{rule.id}:batch:{batch.id}:deadline:{batch.expiry_date.isoformat()}:"
        "threshold:30"
    )
    assert run.result_json == {
        "kind": "medicine_expiry",
        "batch_id": str(batch.id),
        "medicine_id": str(medicine.id),
        "deadline": batch.expiry_date.isoformat(),
        "threshold_days": 30,
    }
    assert outbox.workflow_run == run
    assert outbox.payload_json == run.result_json
    assert rule.next_run_at is None


@pytest.mark.django_db
def test_medicine_expiry_workflow_recomputes_stale_due_time_from_inventory_deadline(
    user, mocker
):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    medicine = MedicineItem.objects.create(owner=user, name="滴眼液")
    InventoryBatch.objects.create(medicine=medicine, expiry_date=date(2026, 12, 31))
    rule = create_compiled_rule(
        user,
        suffix="future-expiry",
        slots={"medicine_id": str(medicine.id), "threshold_days": 30},
        next_run_at=NOW,
    )
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(NOW, batch_size=10)

    rule.refresh_from_db()
    assert WorkflowRun.objects.filter(workflow=rule).count() == 0
    assert NotificationOutbox.objects.filter(workflow_run__workflow=rule).count() == 0
    assert rule.next_run_at == datetime(2026, 12, 1, tzinfo=datetime_timezone.utc)


@pytest.mark.django_db
def test_unknown_medication_frequency_keeps_the_due_time(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    rule = create_compiled_rule(
        user,
        suffix="unknown-frequency",
        slots={
            "medicine_name": "Aspirin",
            "dose_text": "100mg",
            "frequency": "weekly",
            "time_of_day": "08:00",
        },
    )
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    with pytest.raises(ValueError, match="unsupported medication frequency: weekly"):
        dispatch_due_workflows(NOW, batch_size=10)

    rule.refresh_from_db()
    assert rule.next_run_at == NOW
    assert WorkflowRun.objects.filter(workflow=rule).count() == 0


@pytest.mark.django_db
def test_daily_medication_preserves_new_york_local_clock_across_dst(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    scheduled_for = datetime(2026, 3, 7, 8, 30, tzinfo=datetime_timezone.utc)
    rule = create_compiled_rule(
        user,
        suffix="new-york-dst",
        slots={
            "medicine_name": "Aspirin",
            "dose_text": "100mg",
            "frequency": "daily",
            "time_of_day": "03:30",
        },
        next_run_at=scheduled_for,
    )
    rule.timezone = "America/New_York"
    rule.save(update_fields=["timezone"])
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(scheduled_for, batch_size=10)

    rule.refresh_from_db()
    expected_local = datetime(2026, 3, 8, 3, 30, tzinfo=ZoneInfo("America/New_York"))
    assert rule.next_run_at == expected_local.astimezone(datetime_timezone.utc)


@pytest.mark.django_db
def test_daily_medication_preserves_asia_local_clock(user, mocker):
    from apps.workflows.services.dispatcher import dispatch_due_workflows

    scheduled_for = datetime(2026, 8, 8, 0, 0, tzinfo=datetime_timezone.utc)
    rule = create_compiled_rule(
        user,
        suffix="shanghai-clock",
        slots={
            "medicine_name": "Aspirin",
            "dose_text": "100mg",
            "frequency": "daily",
            "time_of_day": "08:00",
        },
        next_run_at=scheduled_for,
    )
    rule.timezone = "Asia/Shanghai"
    rule.save(update_fields=["timezone"])
    mocker.patch("apps.workflows.tasks.enqueue_outbox.delay")

    dispatch_due_workflows(scheduled_for, batch_size=10)

    rule.refresh_from_db()
    assert rule.next_run_at == scheduled_for + timedelta(days=1)


def test_dispatch_task_uses_the_dispatcher_with_late_acknowledgement(mocker):
    from apps.workflows.tasks import dispatch_due_workflows_task

    dispatched = mocker.patch(
        "apps.workflows.tasks.dispatch_due_workflows", return_value=["run-id"]
    )
    now = timezone.now()

    assert dispatch_due_workflows_task.run(now.isoformat(), batch_size=4) == ["run-id"]
    dispatched.assert_called_once_with(now, batch_size=4)
    assert dispatch_due_workflows_task.acks_late is True


def test_outbox_task_is_late_acknowledged():
    from apps.workflows.tasks import enqueue_outbox

    assert enqueue_outbox.acks_late is True

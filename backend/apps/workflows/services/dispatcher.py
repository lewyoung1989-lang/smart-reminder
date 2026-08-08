from datetime import datetime, timedelta, timezone as datetime_timezone
from zoneinfo import ZoneInfo

from django.db import transaction

from apps.medicines.models import ExpiryAlertState, InventoryBatch
from apps.medicines.services.expiry_alerts import refresh_expiry_alerts
from apps.reminders.models import ReminderRule
from apps.workflows.domain.schemas import WorkflowSpec
from apps.workflows.models import NotificationOutbox, WorkflowRun
from apps.workflows.services.smart_departure import (
    build_departure_payload,
    next_departure_run_at,
)


def _enqueue_outbox(outbox_id):
    from apps.workflows.tasks import enqueue_outbox

    enqueue_outbox.delay(str(outbox_id))


def _next_daily_run_at(rule, scheduled_for):
    rule_timezone = ZoneInfo(rule.timezone)
    local_scheduled_for = scheduled_for.astimezone(rule_timezone)
    next_local_date = local_scheduled_for.date() + timedelta(days=1)
    next_local = datetime.combine(
        next_local_date,
        local_scheduled_for.timetz().replace(tzinfo=None),
        tzinfo=rule_timezone,
    )
    return next_local.astimezone(datetime_timezone.utc)


def _next_run_at(rule, scheduled_for):
    if not rule.workflow_spec_json:
        return None

    workflow = WorkflowSpec.model_validate(rule.workflow_spec_json)
    if workflow.template_key == "smart_departure":
        return None
    if workflow.template_key == "medicine_expiry":
        return None
    if workflow.template_key == "medication_cycle":
        for node in workflow.nodes:
            if (
                node.id == "medication-schedule"
                and node.type == "trigger.medication_schedule"
            ):
                frequency = node.config.get("frequency")
                if frequency == "daily":
                    return _next_daily_run_at(rule, scheduled_for)
                raise ValueError(
                    f"unsupported medication frequency: {frequency}"
                )
        raise ValueError("medication workflow is missing its schedule trigger")
    raise ValueError(f"unsupported workflow template: {workflow.template_key}")


def _expiry_trigger_config(workflow):
    for node in workflow.nodes:
        if node.id == "expiry-threshold" and node.type == "trigger.expiry_threshold":
            return node.config
    raise ValueError("medicine expiry workflow is missing its threshold trigger")


def _expiry_trigger_at(rule, trigger_date):
    rule_timezone = ZoneInfo(rule.timezone)
    local_trigger = datetime.combine(
        trigger_date,
        datetime.min.time(),
        tzinfo=rule_timezone,
    )
    return local_trigger.astimezone(datetime_timezone.utc)


def _next_medicine_expiry_run_at(rule, workflow, now):
    config = _expiry_trigger_config(workflow)
    medicine_id = config["medicine_id"]
    threshold_days = int(config["threshold_days"])
    today = now.astimezone(ZoneInfo(rule.timezone)).date()
    candidates = []
    for batch in InventoryBatch.objects.filter(
        medicine_id=medicine_id,
        medicine__owner=rule.owner,
    ):
        deadline = batch.effective_deadline
        if deadline is None:
            continue
        trigger_date = deadline - timedelta(days=threshold_days)
        if trigger_date > today:
            candidates.append(_expiry_trigger_at(rule, trigger_date))
    return min(candidates) if candidates else None


def _medicine_expiry_payload(*, batch, medicine_id, deadline, threshold_days):
    return {
        "kind": "medicine_expiry",
        "batch_id": str(batch.id),
        "medicine_id": str(medicine_id),
        "deadline": deadline.isoformat(),
        "threshold_days": threshold_days,
    }


def _dispatch_medicine_expiry_rule(rule, workflow, now):
    config = _expiry_trigger_config(workflow)
    medicine_id = config["medicine_id"]
    threshold_days = int(config["threshold_days"])
    today = now.astimezone(ZoneInfo(rule.timezone)).date()
    dispatched = []

    for batch in InventoryBatch.objects.filter(
        medicine_id=medicine_id,
        medicine__owner=rule.owner,
    ).select_related("medicine"):
        deadline = batch.effective_deadline
        if deadline is None or deadline - timedelta(days=threshold_days) > today:
            continue

        alert = refresh_expiry_alerts(batch=batch, today=today)
        if (
            alert is None
            or alert.status != ExpiryAlertState.Status.ACTIVE
            or alert.threshold_days != threshold_days
            or alert.deadline != deadline
        ):
            continue

        payload = _medicine_expiry_payload(
            batch=batch,
            medicine_id=medicine_id,
            deadline=deadline,
            threshold_days=threshold_days,
        )
        run, _ = WorkflowRun.objects.get_or_create(
            workflow=rule,
            idempotency_key=(
                f"rule:{rule.id}:batch:{batch.id}:deadline:{deadline.isoformat()}:"
                f"threshold:{threshold_days}"
            ),
            defaults={
                "scheduled_for": _expiry_trigger_at(
                    rule,
                    deadline - timedelta(days=threshold_days),
                ),
                "result_json": payload,
            },
        )
        outbox, outbox_created = NotificationOutbox.objects.get_or_create(
            idempotency_key=f"run:{run.id}:notify",
            defaults={
                "workflow_run": run,
                "node_id": "notify",
                "kind": "notification",
                "payload_json": payload,
            },
        )
        dispatched.append(run.id)
        if outbox_created:
            transaction.on_commit(
                lambda outbox_id=outbox.id: _enqueue_outbox(outbox_id)
            )

    rule.next_run_at = _next_medicine_expiry_run_at(rule, workflow, now)
    rule.save(update_fields=["next_run_at"])
    return dispatched


def _dispatch_smart_departure_rule(rule, workflow, scheduled_for):
    payload = build_departure_payload(workflow)
    run, _ = WorkflowRun.objects.get_or_create(
        workflow=rule,
        idempotency_key=f"rule:{rule.id}:{scheduled_for.isoformat()}:scheduled",
        defaults={"scheduled_for": scheduled_for, "result_json": payload},
    )
    outbox, outbox_created = NotificationOutbox.objects.get_or_create(
        idempotency_key=f"run:{run.id}:notify",
        defaults={
            "workflow_run": run,
            "node_id": "notify",
            "kind": "notification",
            "payload_json": payload,
        },
    )
    rule.next_run_at = next_departure_run_at(workflow, scheduled_for)
    rule.save(update_fields=["next_run_at"])
    if outbox_created:
        transaction.on_commit(
            lambda outbox_id=outbox.id: _enqueue_outbox(outbox_id)
        )
    return run.id


def dispatch_due_workflows(now, batch_size):
    """Persist the single scheduled occurrence for each currently due workflow."""
    due_rules = (
        ReminderRule.objects.select_for_update(skip_locked=True)
        .filter(
            enabled=True,
            workflow_draft__isnull=False,
            next_run_at__isnull=False,
            next_run_at__lte=now,
            cancelled_at__isnull=True,
            paused_reason__isnull=True,
        )
        .order_by("next_run_at", "id")[:batch_size]
    )

    dispatched = []
    with transaction.atomic():
        for rule in due_rules:
            scheduled_for = rule.next_run_at
            workflow = (
                WorkflowSpec.model_validate(rule.workflow_spec_json)
                if rule.workflow_spec_json
                else None
            )
            if workflow and workflow.template_key == "medicine_expiry":
                dispatched.extend(_dispatch_medicine_expiry_rule(rule, workflow, now))
                continue
            if workflow and workflow.template_key == "smart_departure":
                dispatched.append(
                    _dispatch_smart_departure_rule(rule, workflow, scheduled_for)
                )
                continue

            run, _ = WorkflowRun.objects.get_or_create(
                workflow=rule,
                idempotency_key=(
                    f"rule:{rule.id}:{scheduled_for.isoformat()}:scheduled"
                ),
                defaults={"scheduled_for": scheduled_for},
            )
            outbox, outbox_created = NotificationOutbox.objects.get_or_create(
                idempotency_key=f"run:{run.id}:notify",
                defaults={
                    "workflow_run": run,
                    "node_id": "notify",
                    "kind": "notification",
                    "payload_json": {},
                },
            )
            rule.next_run_at = _next_run_at(rule, scheduled_for)
            rule.save(update_fields=["next_run_at"])
            dispatched.append(run.id)
            if outbox_created:
                transaction.on_commit(
                    lambda outbox_id=outbox.id: _enqueue_outbox(outbox_id)
                )

    return dispatched

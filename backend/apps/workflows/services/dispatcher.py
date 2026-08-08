from datetime import datetime, timedelta, timezone as datetime_timezone
from zoneinfo import ZoneInfo

from django.db import transaction

from apps.reminders.models import ReminderRule
from apps.workflows.domain.schemas import WorkflowSpec
from apps.workflows.models import NotificationOutbox, WorkflowRun


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

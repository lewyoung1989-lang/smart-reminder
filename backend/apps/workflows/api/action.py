from datetime import timedelta
from zoneinfo import ZoneInfo

from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.medication.models import MedicationOccurrence
from apps.medicines.models import ExpiryAlertState, LowStockAlertState
from apps.reminders.models import ReminderRule
from apps.workflows.models import NotificationOutbox


LOCAL_TIMEZONE = ZoneInfo("Asia/Shanghai")
DEFAULT_LIMIT = 50
MAX_LIMIT = 50


def _as_local_iso(value):
    return value.astimezone(LOCAL_TIMEZONE).isoformat() if value is not None else None


def _pagination(request):
    values = {}
    for name, default in (("offset", 0), ("limit", DEFAULT_LIMIT)):
        raw_value = request.query_params.get(name, str(default))
        try:
            values[name] = int(raw_value)
        except ValueError as exc:
            raise ValidationError({name: "必须是整数"}) from exc
    if values["offset"] < 0:
        raise ValidationError({"offset": "必须是非负整数"})
    if not 1 <= values["limit"] <= MAX_LIMIT:
        raise ValidationError({"limit": f"必须介于 1 和 {MAX_LIMIT} 之间"})
    return values["offset"], values["limit"]


def _paginate_window(items, *, request, offset, limit):
    page = items[offset : offset + limit]
    next_url = None
    if len(items) > offset + limit:
        query = request.query_params.copy()
        query["offset"] = offset + limit
        query["limit"] = limit
        next_url = request.build_absolute_uri(f"{request.path}?{query.urlencode()}")
    return {"next": next_url, "results": page}


class TodayActionCenterView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        offset, limit = _pagination(request)
        window = offset + limit + 1
        now = timezone.now()
        local_now = now.astimezone(LOCAL_TIMEZONE)
        today_start = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
        tomorrow_start = today_start + timedelta(days=1)
        failed_outbox = NotificationOutbox.objects.filter(
            workflow_run__workflow__owner=request.user,
            status=NotificationOutbox.Status.FAILED,
        ).select_related("workflow_run__workflow")
        paused_rules = ReminderRule.objects.filter(
            owner=request.user,
            template_key__isnull=False,
            enabled=False,
            paused_reason__isnull=False,
        )
        due_outbox = NotificationOutbox.objects.filter(
            workflow_run__workflow__owner=request.user,
            status=NotificationOutbox.Status.PENDING,
        ).filter(Q(next_attempt_at__isnull=True) | Q(next_attempt_at__lte=now)).select_related(
            "workflow_run__workflow"
        )
        upcoming_rules = ReminderRule.objects.filter(
            owner=request.user,
            template_key__isnull=False,
            enabled=True,
            next_run_at__gt=now,
            next_run_at__lt=tomorrow_start,
        ).exclude(template_key="medication_cycle")
        ordinary_reminders = ReminderRule.objects.filter(
            owner=request.user,
            workflow_draft__isnull=True,
            enabled=True,
            cancelled_at__isnull=True,
            completed_at__isnull=True,
            scheduled_at__isnull=False,
        ).filter(Q(template_key__isnull=True) | Q(template_key=""))
        completed_reminders = ReminderRule.objects.filter(
            owner=request.user,
            workflow_draft__isnull=True,
            completed_at__gte=today_start,
            completed_at__lt=tomorrow_start,
            scheduled_at__isnull=False,
        ).filter(Q(template_key__isnull=True) | Q(template_key=""))
        due_medication = MedicationOccurrence.objects.filter(
            plan__owner=request.user,
            plan__enabled=True,
            status=MedicationOccurrence.Status.PENDING,
            scheduled_at__gte=today_start,
            scheduled_at__lte=now,
        ).select_related("plan__medicine")
        active_expiry_alerts = ExpiryAlertState.objects.filter(
            status=ExpiryAlertState.Status.ACTIVE,
        ).filter(
            Q(batch__medicine__owner=request.user)
            | Q(batch__medicine__family__members__user=request.user)
        ).distinct().select_related("batch__medicine")
        active_low_stock_alerts = LowStockAlertState.objects.filter(
            status=LowStockAlertState.Status.ACTIVE,
        ).filter(
            Q(medicine__owner=request.user)
            | Q(medicine__family__members__user=request.user)
        ).distinct().select_related("medicine")
        upcoming_medication = MedicationOccurrence.objects.filter(
            plan__owner=request.user,
            plan__enabled=True,
            status=MedicationOccurrence.Status.PENDING,
            scheduled_at__gt=now,
            scheduled_at__lt=tomorrow_start,
        ).select_related("plan__medicine")

        need_decision = [
            {
                "id": str(outbox.id),
                "title": outbox.workflow_run.workflow.title,
                "kind": "delivery",
                "status": "failed",
                "occurred_at": _as_local_iso(outbox.created_at),
                "action_target": {
                    "resource": "notification_outbox",
                    "id": str(outbox.id),
                },
            }
            for outbox in failed_outbox.order_by("-created_at", "-id")[:window]
        ]
        need_decision.extend(
            {
                "id": str(rule.id),
                "title": rule.title,
                "kind": "workflow",
                "status": "paused",
                "occurred_at": _as_local_iso(rule.next_run_at),
                "action_target": {"resource": "workflow", "id": str(rule.id)},
            }
            for rule in paused_rules.order_by("next_run_at", "id")[:window]
        )
        need_decision.extend(
            {
                "id": str(occurrence.id),
                "title": _medication_title(occurrence),
                "kind": "medication",
                "status": "due",
                "occurred_at": _as_local_iso(occurrence.scheduled_at),
                "action_target": {
                    "resource": "medication_occurrence",
                    "id": str(occurrence.id),
                },
            }
            for occurrence in due_medication.order_by("scheduled_at", "id")[:window]
        )
        need_decision.extend(
            {
                "id": str(rule.id),
                "title": rule.title,
                "kind": "reminder",
                "status": "due",
                "occurred_at": _as_local_iso(rule.scheduled_at),
                "action_target": {
                    "resource": "reminder",
                    "id": str(rule.id),
                    "action": "complete",
                },
                "secondary_action_target": {
                    "resource": "reminder",
                    "id": str(rule.id),
                    "action": "snooze",
                },
            }
            for rule in ordinary_reminders.filter(scheduled_at__lte=now).order_by(
                "scheduled_at", "id"
            )[:window]
        )
        need_decision.extend(
            {
                "id": str(alert.id),
                "title": _expiry_title(alert),
                "kind": "medicine_expiry",
                "status": "expired" if alert.threshold_days == 0 else "expiring_soon",
                "occurred_at": alert.deadline.isoformat(),
                "action_target": {
                    "resource": "inventory_batch",
                    "id": str(alert.batch_id),
                },
            }
            for alert in active_expiry_alerts.order_by("deadline", "id")[:window]
        )
        need_decision.extend(
            {
                "id": str(alert.id),
                "title": _low_stock_title(alert),
                "kind": "medicine_low_stock",
                "status": "low_stock",
                "occurred_at": _as_local_iso(alert.activated_at or alert.created_at),
                "action_target": {
                    "resource": "low_stock_alert",
                    "id": str(alert.id),
                },
            }
            for alert in active_low_stock_alerts.order_by(
                "days_remaining", "medicine__name", "id"
            )[:window]
        )

        upcoming = [
            (
                outbox.next_attempt_at or outbox.created_at,
                str(outbox.id),
                {
                    "id": str(outbox.id),
                    "title": outbox.workflow_run.workflow.title,
                    "kind": "delivery",
                    "status": "pending",
                    "occurred_at": _as_local_iso(outbox.next_attempt_at),
                },
            )
            for outbox in due_outbox.order_by("next_attempt_at", "id")[:window]
        ]
        upcoming.extend(
            (
                rule.next_run_at,
                str(rule.id),
                {
                    "id": str(rule.id),
                    "title": rule.title,
                    "subtitle": _workflow_timeline_subtitle(rule),
                    "kind": "workflow",
                    "status": "scheduled",
                    "occurred_at": _as_local_iso(rule.next_run_at),
                    "action_target": {"resource": "workflow", "id": str(rule.id)},
                },
            )
            for rule in upcoming_rules.order_by("next_run_at", "id")[:window]
        )
        upcoming.extend(
            (
                rule.scheduled_at,
                str(rule.id),
                {
                    "id": str(rule.id),
                    "title": rule.title,
                    "kind": "reminder",
                    "status": "scheduled",
                    "occurred_at": _as_local_iso(rule.scheduled_at),
                },
            )
            for rule in ordinary_reminders.filter(
                scheduled_at__gt=now,
                scheduled_at__lt=tomorrow_start,
            ).order_by("scheduled_at", "id")[:window]
        )
        upcoming.extend(
            (
                rule.completed_at,
                str(rule.id),
                {
                    "id": str(rule.id),
                    "title": rule.title,
                    "kind": "reminder",
                    "status": "completed",
                    "occurred_at": _as_local_iso(rule.completed_at),
                },
            )
            for rule in completed_reminders.order_by("-completed_at", "id")[:window]
        )
        upcoming.extend(
            (
                occurrence.scheduled_at,
                str(occurrence.id),
                {
                    "id": str(occurrence.id),
                    "title": _medication_title(occurrence),
                    "kind": "medication",
                    "status": "scheduled",
                    "occurred_at": _as_local_iso(occurrence.scheduled_at),
                },
            )
            for occurrence in upcoming_medication.order_by("scheduled_at", "id")[:window]
        )
        upcoming.sort(key=lambda item: (item[0], item[1]))

        return Response(
            {
                "need_decision": _paginate_window(
                    need_decision, request=request, offset=offset, limit=limit
                ),
                "upcoming": _paginate_window(
                    [item[2] for item in upcoming],
                    request=request,
                    offset=offset,
                    limit=limit,
                ),
            }
        )


def _medication_title(occurrence):
    name = occurrence.plan.medicine_name
    if not name and occurrence.plan.medicine_id:
        name = occurrence.plan.medicine.name
    if not name:
        name = "药品"
    return f"服用{name}（{occurrence.plan.dosage_text}）"


def _workflow_timeline_subtitle(rule):
    task = getattr(rule.workflow_draft, "task_spec_json", None)
    slots = task.get("slots") if isinstance(task, dict) else {}
    if not isinstance(slots, dict):
        slots = {}
    if rule.template_key == "medication_cycle":
        parts = [
            value
            for value in (
                slots.get("medicine_name"),
                slots.get("dose_text"),
            )
            if isinstance(value, str) and value
        ]
        return " · ".join(parts) if parts else "用药计划"
    if rule.template_key == "smart_departure":
        destination = slots.get("destination_text")
        if isinstance(destination, str) and destination:
            return destination
        return "路线与天气提醒"
    if rule.template_key == "medicine_expiry":
        return "药品有效期提醒"
    return "提醒计划"


def _expiry_title(alert):
    if alert.threshold_days == 0:
        return f"{alert.batch.medicine.name}已到期，请确认是否已处理"
    return f"{alert.batch.medicine.name}有效期还有{alert.threshold_days}天，请确认库存"


def _low_stock_title(alert):
    days = format(alert.days_remaining.normalize(), "f")
    remaining = format(alert.remaining_quantity.normalize(), "f")
    return f"{alert.medicine.name}余量不足，还能用约{days}天（剩余{remaining}{alert.unit_name}）"

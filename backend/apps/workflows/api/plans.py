from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reminders.models import ReminderRule


def _workflow_rules(user):
    return (
        ReminderRule.objects.filter(
            owner=user,
            workflow_draft__isnull=False,
            template_key__isnull=False,
        )
        .select_related("workflow_draft")
        .order_by("enabled", "next_run_at", "-created_at")
    )


def _summary(rule: ReminderRule) -> dict:
    return {
        "id": str(rule.id),
        "title": rule.title,
        "subtitle": _subtitle(rule),
        "next_run_at": _next_run_at(rule).isoformat(),
        "status": _status(rule),
        "kind": _kind(rule),
    }


def _detail(rule: ReminderRule) -> dict:
    return {
        "summary": _summary(rule),
        "arrival_label": _arrival_label(rule),
        "destination": _slots(rule).get("destination_text"),
        "queried_sources": _queried_sources(rule),
        "reminder_label": _reminder_label(rule),
        "executions": [],
        "is_degraded": False,
        "degradation_message": None,
    }


def _slots(rule: ReminderRule) -> dict:
    task = getattr(rule.workflow_draft, "task_spec_json", None)
    if not isinstance(task, dict):
        return {}
    slots = task.get("slots")
    return slots if isinstance(slots, dict) else {}


def _next_run_at(rule: ReminderRule):
    return rule.next_run_at or rule.scheduled_at or rule.created_at


def _status(rule: ReminderRule) -> str:
    if rule.enabled:
        return "active"
    return "paused"


def _kind(rule: ReminderRule) -> str:
    return {
        "medication_cycle": "medication",
        "smart_departure": "departure",
    }.get(rule.template_key or "", "reminder")


def _subtitle(rule: ReminderRule) -> str:
    slots = _slots(rule)
    if rule.template_key == "medication_cycle":
        medicine = slots.get("medicine_name")
        dose = slots.get("dose_text")
        parts = [part for part in (medicine, dose) if isinstance(part, str) and part]
        return " · ".join(parts) if parts else "周期用药"
    if rule.template_key == "smart_departure":
        destination = slots.get("destination_text")
        if isinstance(destination, str) and destination:
            return destination
        return "路线与天气提醒"
    if rule.template_key == "medicine_expiry":
        return "药品有效期提醒"
    return "周期提醒"


def _reminder_label(rule: ReminderRule) -> str:
    slots = _slots(rule)
    if rule.template_key == "medication_cycle":
        frequency = slots.get("frequency")
        time_of_day = slots.get("time_of_day")
        if frequency == "daily" and isinstance(time_of_day, str):
            return f"每天 {time_of_day} 通知提醒"
        if frequency == "daily":
            return "每天通知提醒"
        return "按用药周期通知提醒"
    if rule.template_key == "smart_departure":
        return "按出发前检查点提醒"
    if rule.template_key == "medicine_expiry":
        return "按药品有效期提前提醒"
    return "按计划时间通知提醒"


def _arrival_label(rule: ReminderRule) -> str | None:
    slots = _slots(rule)
    arrival = slots.get("arrival_time")
    if not isinstance(arrival, str):
        return None
    try:
        value = timezone.datetime.fromisoformat(arrival)
    except ValueError:
        return None
    return f"{value.hour:02d}:{value.minute:02d}"


def _queried_sources(rule: ReminderRule) -> list[str]:
    if rule.template_key == "smart_departure":
        return ["路线", "天气"]
    if rule.template_key == "medicine_expiry":
        return ["药箱"]
    return []


class PlanListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(
            {
                "results": [_summary(rule) for rule in _workflow_rules(request.user)],
                "is_offline": False,
            },
            status=status.HTTP_200_OK,
        )


class PlanDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, plan_id):
        try:
            rule = _workflow_rules(request.user).get(id=plan_id)
        except ReminderRule.DoesNotExist:
            return Response({"detail": "未找到该周期计划"}, status=status.HTTP_404_NOT_FOUND)
        return Response(_detail(rule), status=status.HTTP_200_OK)

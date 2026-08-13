from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reminders.models import ReminderRule
from apps.workflows.models import WorkflowRun
from apps.workflows.domain.schemas import WorkflowSpec

from .views import _initial_next_run_at


def _workflow_rules(user):
    return (
        ReminderRule.objects.filter(
            owner=user,
            workflow_draft__isnull=False,
            template_key__isnull=False,
            cancelled_at__isnull=True,
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
    executions = [
        _execution(run)
        for run in rule.workflow_runs.order_by("-started_at", "-id")[:20]
    ]
    latest_result = executions[0] if executions else None
    return {
        "summary": _summary(rule),
        "arrival_label": _arrival_label(rule),
        "destination": _slots(rule).get("destination_text"),
        "queried_sources": _queried_sources(rule),
        "reminder_label": _reminder_label(rule),
        "executions": executions,
        "is_degraded": (
            latest_result is not None and latest_result["status"] == "degraded"
        ),
        "degradation_message": (
            latest_result["message"]
            if latest_result is not None and latest_result["status"] == "degraded"
            else None
        ),
        "notification_schedule": _notification_schedule(rule),
        "source_text": getattr(rule.workflow_draft, "source_text", ""),
    }


def _execution(run: WorkflowRun) -> dict:
    result = run.result_json if isinstance(run.result_json, dict) else {}
    degraded = _result_is_degraded(result)
    status_value = _execution_status(run, degraded)
    return {
        "started_at": (
            run.started_at or run.scheduled_for or run.workflow.created_at
        ).isoformat(),
        "status": status_value,
        "message": _execution_message(status_value),
    }


def _execution_status(run: WorkflowRun, degraded: bool) -> str:
    if run.status == WorkflowRun.Status.SUCCEEDED:
        return "degraded" if degraded else "completed"
    return {
        WorkflowRun.Status.PENDING: "pending",
        WorkflowRun.Status.RUNNING: "running",
        WorkflowRun.Status.CANCELLED: "cancelled",
    }.get(run.status, "failed")


def _result_is_degraded(result: dict) -> bool:
    route = result.get("route") if isinstance(result.get("route"), dict) else {}
    weather = result.get("weather") if isinstance(result.get("weather"), dict) else {}
    return route.get("status") == "fallback_static" or weather.get("status") == "unavailable"


def _execution_message(status_value: str) -> str:
    return {
        "pending": "等待执行",
        "running": "正在执行",
        "completed": "计划已按时执行",
        "degraded": "外部信息不可用，已按降级策略继续提醒",
        "cancelled": "本次执行已取消",
        "failed": "执行失败，系统将按策略重试",
    }[status_value]


def _notification_schedule(rule: ReminderRule) -> dict | None:
    slots = _slots(rule)
    if rule.template_key == "medication_cycle":
        time_of_day = slots.get("time_of_day")
        if isinstance(time_of_day, str) and rule.next_run_at is not None:
            return {
                "scheduled_at": rule.next_run_at.isoformat(),
                "repeat": "daily",
                "title": rule.title,
                "timezone": rule.timezone,
            }
    if rule.next_run_at is not None:
        return {
            "scheduled_at": rule.next_run_at.isoformat(),
            "repeat": "none",
            "title": rule.title,
            "timezone": rule.timezone,
        }
    return None


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
            return Response(
                {"detail": "未找到该周期计划"},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(_detail(rule), status=status.HTTP_200_OK)

    def delete(self, request, plan_id):
        try:
            rule = _workflow_rules(request.user).get(id=plan_id)
        except ReminderRule.DoesNotExist:
            return Response(
                {"detail": "未找到该周期计划"},
                status=status.HTTP_404_NOT_FOUND,
            )
        rule.enabled = False
        rule.cancelled_at = timezone.now()
        rule.paused_reason = "user_deleted"
        rule.revision = (rule.revision or 0) + 1
        rule.save(update_fields=["enabled", "cancelled_at", "paused_reason", "revision"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class PlanPauseView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, plan_id):
        try:
            rule = _workflow_rules(request.user).get(id=plan_id)
        except ReminderRule.DoesNotExist:
            return Response(
                {"detail": "未找到该周期计划"},
                status=status.HTTP_404_NOT_FOUND,
            )
        rule.enabled = False
        rule.paused_reason = "user_paused"
        rule.revision = (rule.revision or 0) + 1
        rule.save(update_fields=["enabled", "paused_reason", "revision"])
        return Response(_detail(rule), status=status.HTTP_200_OK)


class PlanResumeView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, plan_id):
        try:
            rule = _workflow_rules(request.user).get(id=plan_id)
        except ReminderRule.DoesNotExist:
            return Response({"detail": "未找到该周期计划"}, status=status.HTTP_404_NOT_FOUND)
        try:
            workflow = WorkflowSpec.model_validate(rule.workflow_spec_json)
            rule.next_run_at = _initial_next_run_at(workflow, timezone.now())
        except (ValueError, TypeError):
            return Response(
                {"code": "plan_invalid", "detail": "计划配置已失效，请重新创建"},
                status=status.HTTP_409_CONFLICT,
            )
        rule.enabled = True
        rule.paused_reason = None
        rule.revision = (rule.revision or 0) + 1
        rule.save(
            update_fields=["enabled", "paused_reason", "next_run_at", "revision"]
        )
        return Response(_detail(rule), status=status.HTTP_200_OK)

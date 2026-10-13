from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Q
from django.db.models.functions import Coalesce
from django.utils import timezone
from pydantic import ValidationError as PydanticValidationError
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.medication.models import MedicationOccurrence, MedicationPlan
from apps.medication.services.occurrences import materialize_occurrences
from apps.medication.services.workflow_plans import update_medication_plan_for_workflow
from apps.reminders.api.serializers import UpdatePlanFromWorkflowDraftSerializer
from apps.reminders.models import ReminderRule
from apps.workflows.domain.schemas import TaskSpec, WorkflowSpec
from apps.workflows.models import WorkflowDraft, WorkflowRun
from apps.workflows.services.compiler import WorkflowCompileError, WorkflowCompiler
from apps.workflows.services.medication_schedule import (
    medication_times_from_config,
    next_daily_occurrences,
)
from apps.workflows.services.policy import evaluate

from .views import WORKFLOW_SCOPE, _initial_next_run_at, _policy_json


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


def _medication_executions(rule: ReminderRule) -> list[dict]:
    medication_plan = MedicationPlan.objects.filter(
        source_workflow_draft=rule.workflow_draft
    ).first()
    if medication_plan is None and rule.owner:
        slots = _slots(rule)
        medicine_name = slots.get("medicine_name")
        if medicine_name:
            medication_plan = (
                MedicationPlan.objects.filter(
                    owner=rule.owner,
                    medicine_name=medicine_name,
                )
                .order_by("-created_at")
                .first()
            )

    if medication_plan is None:
        return []

    now = timezone.now()
    occurrences = (
        medication_plan.occurrences.filter(
            Q(scheduled_at__lte=now) | ~Q(status=MedicationOccurrence.Status.PENDING)
        )
        .order_by("-scheduled_at")[:20]
    )

    items = []
    for occ in occurrences:
        if occ.status == MedicationOccurrence.Status.TAKEN:
            status_value = "completed"
            message = "已按时服药"
        elif occ.status == MedicationOccurrence.Status.SKIPPED:
            status_value = "cancelled"
            message = "已跳过服药"
        elif occ.status == MedicationOccurrence.Status.MISSED:
            status_value = "failed"
            message = "未按时服药"
        else:
            status_value = "pending"
            message = "等待执行"

        items.append(
            {
                "started_at": occ.scheduled_at.isoformat(),
                "status": status_value,
                "message": message,
            }
        )
    return items


def _detail(rule: ReminderRule) -> dict:
    executions = []
    if rule.template_key == "medication_cycle":
        executions = _medication_executions(rule)

    if not executions:
        executions = [
            _execution(run)
            for run in rule.workflow_runs.annotate(
                effective_time=Coalesce(
                    "started_at", "scheduled_for", "workflow__created_at"
                )
            ).order_by("-effective_time", "-id")[:20]
        ]
    latest_result = executions[0] if executions else None
    return {
        "summary": _summary(rule),
        "arrival_label": _arrival_label(rule),
        "destination": _slots(rule).get("destination_text"),
        "dose_label": _dose_label(rule),
        "medication_config": _medication_config(rule),
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


def _medication_config(rule: ReminderRule) -> dict | None:
    if rule.template_key != "medication_cycle":
        return None
    slots = _slots(rule)
    try:
        times = medication_times_from_config(slots)
    except ValueError:
        times = []
    medicine_name = slots.get("medicine_name") or rule.title.replace("服药提醒", "")
    dose_text = slots.get("dose_text") or ""
    return {
        "medicine_name": medicine_name,
        "dose_text": dose_text,
        "times": times,
    }


def _dose_label(rule: ReminderRule) -> str | None:
    slots = _slots(rule)
    dose = slots.get("dose_text")
    if isinstance(dose, str) and dose.strip():
        return dose.strip()
    return None


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
    return (
        route.get("status") == "fallback_static"
        or weather.get("status") == "unavailable"
    )


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
        try:
            times = medication_times_from_config(slots)
        except ValueError:
            times = []
        if times and rule.next_run_at is not None:
            scheduled_times = next_daily_occurrences(
                times=times,
                timezone_name=rule.timezone,
                after=timezone.now(),
            )
            schedule = {
                "scheduled_at": rule.next_run_at.isoformat(),
                "repeat": "daily",
                "title": rule.title,
                "timezone": rule.timezone,
            }
            if len(scheduled_times) > 1:
                schedule["scheduled_times"] = [
                    value.isoformat() for value in scheduled_times
                ]
            return schedule
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
        try:
            times = medication_times_from_config(slots)
        except ValueError:
            times = []
        if frequency == "daily" and times:
            return f"每天 {'、'.join(times)} 通知提醒"
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
        with transaction.atomic():
            rule.enabled = False
            rule.cancelled_at = timezone.now()
            rule.paused_reason = "user_deleted"
            rule.revision = (rule.revision or 0) + 1
            rule.save(
                update_fields=[
                    "enabled",
                    "cancelled_at",
                    "paused_reason",
                    "revision",
                ]
            )
            _set_medication_plan_enabled(rule, False)
        return Response(status=status.HTTP_204_NO_CONTENT)

    def put(self, request, plan_id):
        serializer = UpdatePlanFromWorkflowDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        draft_id = serializer.validated_data["workflow_draft_id"]

        with transaction.atomic():
            try:
                rule = (
                    _workflow_rules(request.user)
                    .select_for_update()
                    .get(id=plan_id)
                )
            except ReminderRule.DoesNotExist:
                return Response(
                    {"detail": "未找到该周期计划"},
                    status=status.HTTP_404_NOT_FOUND,
                )
            try:
                draft = WorkflowDraft.objects.select_for_update().get(
                    id=draft_id,
                    user=request.user,
                )
            except WorkflowDraft.DoesNotExist:
                return Response(
                    {"detail": "未找到该工作流草稿"},
                    status=status.HTTP_404_NOT_FOUND,
                )
            if (
                ReminderRule.objects.filter(workflow_draft=draft)
                .exclude(id=rule.id)
                .exists()
            ):
                return Response(
                    {
                        "code": "workflow_draft_already_confirmed",
                        "detail": "这个草稿已被其他计划使用",
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            now = timezone.now()
            if draft.expires_at <= now:
                draft.status = WorkflowDraft.Status.EXPIRED
                draft.save(update_fields=["status"])
                return Response(
                    {
                        "code": "workflow_draft_expired",
                        "detail": "工作流草稿已过期",
                    },
                    status=status.HTTP_410_GONE,
                )

            try:
                task = TaskSpec.model_validate(draft.task_spec_json)
            except PydanticValidationError:
                return Response(
                    {"code": "workflow_draft_invalid"},
                    status=status.HTTP_409_CONFLICT,
                )
            if task.ambiguities:
                return Response(
                    {"code": "workflow_needs_clarification"},
                    status=status.HTTP_409_CONFLICT,
                )

            try:
                stored_workflow = WorkflowSpec.model_validate(draft.workflow_spec_json)
                workflow = WorkflowCompiler().compile(task)
            except (PydanticValidationError, WorkflowCompileError):
                return Response(
                    {"code": "workflow_needs_clarification"},
                    status=status.HTTP_409_CONFLICT,
                )
            if stored_workflow != workflow:
                return Response(
                    {"code": "workflow_needs_clarification"},
                    status=status.HTTP_409_CONFLICT,
                )
            if workflow.template_key != rule.template_key:
                return Response(
                    {
                        "code": "plan_template_change_unsupported",
                        "detail": "暂不支持把计划修改为另一种类型，请新建计划",
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            decision = evaluate(request.user, task, workflow, now, WORKFLOW_SCOPE)
            if decision.decision == "needs_clarification":
                return Response(
                    {"code": "workflow_needs_clarification"},
                    status=status.HTTP_409_CONFLICT,
                )
            try:
                next_run_at = _initial_next_run_at(workflow, now)
            except ValueError:
                return Response(
                    {"code": "workflow_draft_invalid"},
                    status=status.HTTP_409_CONFLICT,
                )

            previous_draft = rule.workflow_draft
            rule.title = task.title
            rule.timezone = workflow.timezone
            rule.template_version = workflow.template_version
            rule.schema_version = workflow.schema_version
            rule.workflow_spec_json = workflow.model_dump(mode="json")
            rule.next_run_at = next_run_at
            rule.workflow_draft = draft
            rule.revision = (rule.revision or 0) + 1
            rule.save(
                update_fields=[
                    "title",
                    "timezone",
                    "template_version",
                    "schema_version",
                    "workflow_spec_json",
                    "next_run_at",
                    "workflow_draft",
                    "revision",
                ]
            )
            draft.policy_json = _policy_json(decision)
            draft.status = WorkflowDraft.Status.CONFIRMED
            draft.confirmed_at = now
            draft.save(update_fields=["policy_json", "status", "confirmed_at"])
            update_medication_plan_for_workflow(
                previous_draft=previous_draft,
                draft=draft,
                task=task,
                now=now,
                enabled=rule.enabled,
            )
            WorkflowRun.objects.filter(
                workflow=rule,
                status__in=[WorkflowRun.Status.PENDING, WorkflowRun.Status.RUNNING],
            ).update(status=WorkflowRun.Status.CANCELLED)

        return Response(_detail(rule), status=status.HTTP_200_OK)

    def patch(self, request, plan_id):
        with transaction.atomic():
            try:
                rule = (
                    _workflow_rules(request.user)
                    .select_for_update()
                    .get(id=plan_id)
                )
            except ReminderRule.DoesNotExist:
                return Response(
                    {"detail": "未找到该周期计划"},
                    status=status.HTTP_404_NOT_FOUND,
                )

            if rule.template_key != "medication_cycle":
                return Response(
                    {"detail": "当前仅支持直接编辑用药计划"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            data = request.data
            medicine_name = data.get("medicine_name")
            dose_text = data.get("dose_text")
            times = data.get("times")

            if not isinstance(medicine_name, str) or not medicine_name.strip():
                return Response(
                    {"detail": "药品名称不能为空"},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if not isinstance(dose_text, str) or not dose_text.strip():
                return Response(
                    {"detail": "单次剂量不能为空"},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if not isinstance(times, list) or not times or not all(isinstance(t, str) for t in times):
                return Response(
                    {"detail": "提醒时间不能为空且必须是有效的列表"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            medicine_name = medicine_name.strip()
            dose_text = dose_text.strip()
            valid_times = []
            for t in times:
                try:
                    parsed_time = timezone.datetime.strptime(t.strip(), "%H:%M").time()
                    normalized = f"{parsed_time.hour:02d}:{parsed_time.minute:02d}"
                    if normalized not in valid_times:
                        valid_times.append(normalized)
                except ValueError:
                    return Response(
                        {"detail": f"无效的时间格式: {t}，应为 HH:MM"},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
            valid_times.sort()
            if not valid_times:
                return Response(
                    {"detail": "至少需要一个有效的提醒时间"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            now = timezone.now()
            draft = rule.workflow_draft
            task_dict = draft.task_spec_json if isinstance(draft.task_spec_json, dict) else {}
            slots = task_dict.get("slots", {})
            slots["medicine_name"] = medicine_name
            slots["dose_text"] = dose_text
            slots["times"] = valid_times
            slots["time_of_day"] = valid_times[0]
            slots["frequency"] = "daily"
            task_dict["slots"] = slots
            task_dict["title"] = f"{medicine_name}服药提醒"
            task_dict["template_hint"] = "medication_cycle"
            task_dict["requested_capabilities"] = ["medicine.schedule", "notification.important"]
            task_dict["ambiguities"] = []

            task = TaskSpec.model_validate(task_dict)
            workflow = WorkflowCompiler().compile(task)
            next_run_at = _initial_next_run_at(workflow, now)

            draft.task_spec_json = task.model_dump(mode="json")
            draft.workflow_spec_json = workflow.model_dump(mode="json")
            draft.status = WorkflowDraft.Status.CONFIRMED
            draft.confirmed_at = now
            draft.save(update_fields=["task_spec_json", "workflow_spec_json", "status", "confirmed_at"])

            rule.title = task.title
            rule.workflow_spec_json = workflow.model_dump(mode="json")
            rule.next_run_at = next_run_at
            rule.revision = (rule.revision or 0) + 1
            rule.save(update_fields=["title", "workflow_spec_json", "next_run_at", "revision"])

            update_medication_plan_for_workflow(
                previous_draft=draft,
                draft=draft,
                task=task,
                now=now,
                enabled=rule.enabled,
            )
            WorkflowRun.objects.filter(
                workflow=rule,
                status__in=[WorkflowRun.Status.PENDING, WorkflowRun.Status.RUNNING],
            ).update(status=WorkflowRun.Status.CANCELLED)

        return Response(_detail(rule), status=status.HTTP_200_OK)



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
        with transaction.atomic():
            rule.enabled = False
            rule.paused_reason = "user_paused"
            rule.revision = (rule.revision or 0) + 1
            rule.save(update_fields=["enabled", "paused_reason", "revision"])
            _set_medication_plan_enabled(rule, False)
        return Response(_detail(rule), status=status.HTTP_200_OK)


class PlanResumeView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, plan_id):
        try:
            rule = _workflow_rules(request.user).get(id=plan_id)
        except ReminderRule.DoesNotExist:
            return Response(
                {"detail": "未找到该周期计划"},
                status=status.HTTP_404_NOT_FOUND,
            )
        try:
            workflow = WorkflowSpec.model_validate(rule.workflow_spec_json)
            rule.next_run_at = _initial_next_run_at(workflow, timezone.now())
        except (ValueError, TypeError):
            return Response(
                {"code": "plan_invalid", "detail": "计划配置已失效，请重新创建"},
                status=status.HTTP_409_CONFLICT,
            )
        medication_plan = MedicationPlan.objects.filter(
            source_workflow_draft=rule.workflow_draft
        ).select_related("medicine__family").first()
        if medication_plan is not None:
            medication_plan.enabled = True
            try:
                medication_plan.full_clean()
            except DjangoValidationError:
                return Response(
                    {
                        "code": "medicine_access_lost",
                        "detail": "已无法访问计划关联的药品",
                    },
                    status=status.HTTP_409_CONFLICT,
                )
        with transaction.atomic():
            rule.enabled = True
            rule.paused_reason = None
            rule.revision = (rule.revision or 0) + 1
            rule.save(
                update_fields=["enabled", "paused_reason", "next_run_at", "revision"]
            )
            if medication_plan is not None:
                medication_plan.save(update_fields=["enabled", "updated_at"])
                materialize_occurrences(medication_plan, now=timezone.now())
        return Response(_detail(rule), status=status.HTTP_200_OK)


def _set_medication_plan_enabled(rule, enabled):
    MedicationPlan.objects.filter(
        source_workflow_draft=rule.workflow_draft
    ).update(enabled=enabled, updated_at=timezone.now())

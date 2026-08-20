from datetime import timedelta
from zoneinfo import ZoneInfo

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import CursorPagination
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reminders.domain.schemas import ReminderDraftData
from apps.reminders.domain.intent_parser import ReminderIntentParser
from apps.reminders.models import ReminderDraft, ReminderRule
from apps.reminders.providers.deepseek import DeepSeekReminderIntentProvider
from apps.reminders.providers.natural_language import DeepSeekNaturalLanguageProvider
from apps.reminders.providers.deepseek import DeepSeekResponseError
from apps.reminders.services.draft_service import (
    create_reminder_draft,
    persist_reminder_draft,
)
from apps.workflows.domain.schemas import TaskSpec
from apps.workflows.models import WorkflowDraft
from apps.workflows.services.compiler import WorkflowCompileError, WorkflowCompiler
from apps.workflows.services.policy import evaluate as evaluate_workflow_policy
from apps.workflows.services.task_parser import (
    WorkflowTaskParser,
    looks_like_medicine_name,
)

from .serializers import (
    CreateTextReminderDraftSerializer,
    CreateVoiceReminderDraftSerializer,
    ReminderActionSerializer,
    ReminderRuleSerializer,
)


class PendingReminderPagination(CursorPagination):
    page_size = 50
    ordering = ("scheduled_at", "id")


class ExpiredReminderPagination(CursorPagination):
    page_size = 50
    ordering = ("-scheduled_at", "id")


class CancelledReminderPagination(CursorPagination):
    page_size = 50
    ordering = ("-cancelled_at", "id")


class CompletedReminderPagination(CursorPagination):
    page_size = 50
    ordering = ("-completed_at", "id")


REMINDER_PAGINATORS = {
    "pending": PendingReminderPagination,
    "expired": ExpiredReminderPagination,
    "cancelled": CancelledReminderPagination,
    "completed": CompletedReminderPagination,
}


def _intent_parser() -> ReminderIntentParser:
    if not settings.DEEPSEEK_API_KEY:
        return ReminderIntentParser()
    return ReminderIntentParser(
        DeepSeekReminderIntentProvider(
            api_key=settings.DEEPSEEK_API_KEY,
            base_url=settings.DEEPSEEK_BASE_URL,
            model=settings.DEEPSEEK_MODEL,
            timeout_seconds=settings.DEEPSEEK_TIMEOUT_SECONDS,
        )
    )


def _create_draft_response(*, request, text: str) -> Response:
    created = create_reminder_draft(
        user=request.user,
        text=text,
        parser=_intent_parser(),
        now=timezone.now(),
        timezone="Asia/Shanghai",
    )
    return _response_for_reminder_draft(created)


def _response_for_reminder_draft(created) -> Response:
    draft = created.draft
    return Response(
        {
            "draft_type": "reminder",
            "id": str(draft.id),
            "status": draft.status,
            "expires_at": draft.expires_at.isoformat(),
            "parser_source": created.parser_source,
            "draft": draft.draft_json,
        },
        status=status.HTTP_201_CREATED,
    )


WORKFLOW_ROUTING_SCOPE = {"owner": "self"}


def _clarification_policy_json(task: TaskSpec) -> dict:
    return {
        "decision": "needs_clarification",
        "risk_level": "R2",
        "capability_signature": "",
        "trust_expiry": None,
        "question": task.ambiguities[0] if task.ambiguities else None,
        "scope": WORKFLOW_ROUTING_SCOPE,
    }


def _workflow_draft_response(
    *, request, text: str, task: TaskSpec | None = None
) -> Response | None:
    """Route text with a workflow template intent to the workflow draft flow.

    Returns None when the text does not match any registered workflow
    template, so the caller can fall back to one-time reminder parsing.
    """
    now = timezone.now()
    task_is_deterministic = task is None
    task = task or WorkflowTaskParser().parse(
        text, now=now, timezone="Asia/Shanghai"
    )
    if task.template_hint is None:
        return None
    if task.template_hint == "smart_departure" and task.ambiguities:
        # Incomplete departure expressions fall back to one-time reminder
        # parsing instead of blocking on workflow clarifications.
        return None
    if (
        not task_is_deterministic
        and task.template_hint == "medication_cycle"
        and not any(marker in text for marker in ("吃药", "服药", "服用", "药"))
    ):
        # Expressions like “吃火锅” must not be hijacked by the medication
        # workflow; keep them on the one-time reminder flow unless the
        # matched medicine name or the text itself mentions medicine.
        medicine_name = task.slots.get("medicine_name")
        if not looks_like_medicine_name(medicine_name):
            return None

    if task.ambiguities:
        workflow_json = {}
        policy_json = _clarification_policy_json(task)
    else:
        try:
            workflow = WorkflowCompiler().compile(task)
        except WorkflowCompileError:
            return None
        if task.template_hint != workflow.template_key:
            return None
        decision = evaluate_workflow_policy(
            request.user, task, workflow, now, WORKFLOW_ROUTING_SCOPE
        )
        policy_json = {
            "decision": decision.decision,
            "risk_level": decision.risk_level,
            "capability_signature": decision.capability_signature,
            "trust_expiry": decision.trust_expiry.isoformat()
            if decision.trust_expiry is not None
            else None,
            "question": decision.question,
            "scope": WORKFLOW_ROUTING_SCOPE,
        }
        workflow_json = workflow.model_dump(mode="json")

    draft = WorkflowDraft.objects.create(
        user=request.user,
        source_text=text,
        task_spec_json=task.model_dump(mode="json"),
        workflow_spec_json=workflow_json,
        policy_json=policy_json,
        expires_at=now + timedelta(minutes=30),
    )
    return Response(
        {
            "draft_type": "workflow",
            "id": str(draft.id),
            "status": draft.status,
            "expires_at": draft.expires_at.isoformat(),
            "task": draft.task_spec_json,
            "workflow": draft.workflow_spec_json,
            "policy": draft.policy_json,
        },
        status=status.HTTP_201_CREATED,
    )


def _natural_language_response(*, request, text: str) -> Response:
    """模型负责理解；系统只编译注册工作流或保存待确认提醒草稿。"""
    if settings.DEEPSEEK_API_KEY:
        provider = DeepSeekNaturalLanguageProvider(
            api_key=settings.DEEPSEEK_API_KEY,
            base_url=settings.DEEPSEEK_BASE_URL,
            model=settings.DEEPSEEK_MODEL,
            timeout_seconds=settings.DEEPSEEK_TIMEOUT_SECONDS,
        )
        try:
            result = provider.parse(
                text,
                now=timezone.now(),
                timezone="Asia/Shanghai",
            )
        except DeepSeekResponseError:
            result = None
        if result is not None and result.workflow is not None:
            response = _workflow_draft_response(
                request=request,
                text=text,
                task=result.workflow,
            )
            if response is not None:
                return response
        if result is not None and result.reminder is not None:
            workflow_response = _workflow_draft_response(
                request=request,
                text=text,
            )
            if workflow_response is not None:
                return workflow_response
            created = persist_reminder_draft(
                user=request.user,
                text=text,
                draft_data=result.reminder,
                parser_source="deepseek",
                now=timezone.now(),
            )
            return _response_for_reminder_draft(created)

    workflow_response = _workflow_draft_response(request=request, text=text)
    if workflow_response is not None:
        return workflow_response
    return _create_draft_response(request=request, text=text)


class ReminderDraftListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateTextReminderDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        text = serializer.validated_data["text"]
        return _natural_language_response(request=request, text=text)


class VoiceReminderDraftListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateVoiceReminderDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return _natural_language_response(
            request=request,
            text=serializer.validated_data["transcript"],
        )


class VoiceReminderDraftConfirmView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, draft_id):
        with transaction.atomic():
            try:
                draft = (
                    ReminderDraft.objects.select_for_update()
                    .select_related("session")
                    .get(id=draft_id, session__user=request.user)
                )
            except ReminderDraft.DoesNotExist:
                return Response(
                    {"detail": "未找到该语音草稿"},
                    status=status.HTTP_404_NOT_FOUND,
                )

            existing_rule = ReminderRule.objects.filter(source_draft=draft).first()
            if existing_rule is not None:
                return Response(
                    {"reminder_id": str(existing_rule.id), "status": "confirmed"},
                    status=status.HTTP_200_OK,
                )

            if draft.expires_at <= timezone.now():
                return Response(
                    {"code": "draft_expired", "detail": "语音草稿已过期"},
                    status=status.HTTP_410_GONE,
                )
            if draft.ambiguities_json:
                return Response(
                    {"code": "draft_has_ambiguities", "detail": "请先解决草稿中的歧义"},
                    status=status.HTTP_409_CONFLICT,
                )

            draft_data = ReminderDraftData.model_validate(draft.draft_json)
            if draft_data.schedule is None:
                return Response(
                    {"code": "draft_has_ambiguities", "detail": "请先补充提醒时间"},
                    status=status.HTTP_409_CONFLICT,
                )

            rule = ReminderRule.objects.create(
                owner=request.user,
                title=draft_data.title,
                timezone=draft_data.schedule.timezone,
                schedule_json=draft_data.schedule.model_dump(mode="json"),
                conditions_json=draft_data.precheck.model_dump(mode="json") if draft_data.precheck else {},
                severity=draft_data.severity,
                scheduled_at=draft_data.schedule.local_datetime,
                source_draft=draft,
            )
            draft.status = "confirmed"
            draft.confirmed_at = timezone.now()
            draft.save(update_fields=["status", "confirmed_at"])

        return Response(
            {"reminder_id": str(rule.id), "status": "confirmed"},
            status=status.HTTP_201_CREATED,
        )


class ReminderListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        reminder_status = request.query_params.get("status", "pending")
        if reminder_status not in REMINDER_PAGINATORS:
            raise ValidationError(
                {"status": "状态必须是 pending、expired、cancelled 或 completed"}
            )

        now = timezone.now()
        queryset = ReminderRule.objects.filter(
            owner=request.user,
            workflow_draft__isnull=True,
        )
        if reminder_status == "pending":
            queryset = queryset.filter(
                enabled=True,
                cancelled_at__isnull=True,
                completed_at__isnull=True,
                scheduled_at__gt=now,
            )
        elif reminder_status == "expired":
            queryset = queryset.filter(
                enabled=True,
                cancelled_at__isnull=True,
                completed_at__isnull=True,
                scheduled_at__lte=now,
            )
        elif reminder_status == "cancelled":
            queryset = queryset.filter(
                enabled=False,
                cancelled_at__isnull=False,
            )
        else:
            queryset = queryset.filter(
                enabled=False,
                completed_at__isnull=False,
            )

        paginator = REMINDER_PAGINATORS[reminder_status]()
        page = paginator.paginate_queryset(queryset, request, view=self)
        serializer = ReminderRuleSerializer(
            page,
            many=True,
            context={"now": now},
        )
        return paginator.get_paginated_response(serializer.data)


class ReminderCancelView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, reminder_id):
        with transaction.atomic():
            try:
                rule = ReminderRule.objects.select_for_update().get(
                    id=reminder_id,
                    owner=request.user,
                )
            except ReminderRule.DoesNotExist:
                return Response(
                    {"detail": "未找到该提醒"},
                    status=status.HTTP_404_NOT_FOUND,
                )

            if rule.workflow_draft_id is not None:
                return Response(
                    {
                        "code": "workflow_requires_workflow_api",
                        "detail": "该工作流提醒不能通过旧提醒接口取消",
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            now = timezone.now()
            if rule.completed_at is not None:
                return Response(
                    {
                        "code": "reminder_completed",
                        "detail": "提醒已完成，不能取消",
                    },
                    status=status.HTTP_409_CONFLICT,
                )
            if not rule.enabled and rule.cancelled_at is not None:
                serializer = ReminderRuleSerializer(rule, context={"now": now})
                return Response(serializer.data, status=status.HTTP_200_OK)

            if rule.scheduled_at <= now:
                return Response(
                    {
                        "code": "reminder_expired",
                        "detail": "提醒时间已过，不能取消",
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            rule.enabled = False
            rule.cancelled_at = now
            rule.save(update_fields=["enabled", "cancelled_at"])

        serializer = ReminderRuleSerializer(rule, context={"now": now})
        return Response(serializer.data, status=status.HTTP_200_OK)


class ReminderActionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, reminder_id):
        serializer = ReminderActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data["action"]

        with transaction.atomic():
            try:
                rule = ReminderRule.objects.select_for_update().get(
                    id=reminder_id,
                    owner=request.user,
                )
            except ReminderRule.DoesNotExist:
                return Response(
                    {"detail": "未找到该提醒"},
                    status=status.HTTP_404_NOT_FOUND,
                )

            if rule.workflow_draft_id is not None:
                return Response(
                    {
                        "code": "workflow_requires_workflow_api",
                        "detail": "该工作流提醒不能通过旧提醒接口处理",
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            now = timezone.now()
            if action == "complete":
                if rule.completed_at is None:
                    rule.enabled = False
                    rule.completed_at = now
                    rule.save(update_fields=["enabled", "completed_at"])
                response_status = status.HTTP_200_OK
            else:
                if rule.completed_at is not None:
                    return Response(
                        {
                            "code": "reminder_completed",
                            "detail": "提醒已完成，不能稍后提醒",
                        },
                        status=status.HTTP_409_CONFLICT,
                    )
                if not rule.enabled and rule.cancelled_at is not None:
                    return Response(
                        {
                            "code": "reminder_cancelled",
                            "detail": "提醒已取消，不能稍后提醒",
                        },
                        status=status.HTTP_409_CONFLICT,
                    )
                scheduled_at = now + timedelta(
                    minutes=serializer.validated_data["snooze_minutes"]
                )
                rule.enabled = True
                rule.cancelled_at = None
                rule.scheduled_at = scheduled_at
                rule.schedule_json = {
                    **(rule.schedule_json or {}),
                    "local_datetime": scheduled_at.astimezone(
                        ZoneInfo(rule.timezone)
                    ).isoformat(),
                }
                rule.save(
                    update_fields=[
                        "enabled",
                        "cancelled_at",
                        "scheduled_at",
                        "schedule_json",
                    ]
                )
                response_status = status.HTTP_200_OK

        return Response(
            ReminderRuleSerializer(rule, context={"now": now}).data,
            status=response_status,
        )

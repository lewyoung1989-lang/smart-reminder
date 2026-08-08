from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from django.db import transaction
from django.utils import timezone
from pydantic import ValidationError as PydanticValidationError
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reminders.api.serializers import (
    ConfirmWorkflowDraftSerializer,
    CreateWorkflowDraftSerializer,
)
from apps.reminders.models import ReminderRule
from apps.workflows.domain.schemas import TaskSpec, WorkflowSpec
from apps.workflows.models import TrustGrant, WorkflowDraft
from apps.workflows.services.compiler import WorkflowCompileError, WorkflowCompiler
from apps.workflows.services.policy import PolicyDecision, evaluate
from apps.workflows.services.smart_departure import initial_departure_run_at
from apps.workflows.services.task_parser import WorkflowTaskParser


WORKFLOW_SCOPE = {"owner": "self"}


def _policy_json(decision: PolicyDecision) -> dict:
    return {
        "decision": decision.decision,
        "risk_level": decision.risk_level,
        "capability_signature": decision.capability_signature,
        "trust_expiry": decision.trust_expiry.isoformat()
        if decision.trust_expiry is not None
        else None,
        "question": decision.question,
        "scope": WORKFLOW_SCOPE,
    }


def _clarification_policy(task: TaskSpec) -> dict:
    return {
        "decision": "needs_clarification",
        "risk_level": "R2",
        "capability_signature": "",
        "trust_expiry": None,
        "question": task.ambiguities[0] if task.ambiguities else None,
        "scope": WORKFLOW_SCOPE,
    }


def _initial_next_run_at(workflow: WorkflowSpec, now):
    if workflow.template_key == "medicine_expiry":
        return now
    if workflow.template_key == "medication_cycle":
        for node in workflow.nodes:
            if (
                node.id == "medication-schedule"
                and node.type == "trigger.medication_schedule"
            ):
                time_of_day = node.config.get("time_of_day")
                if not isinstance(time_of_day, str):
                    break
                try:
                    hour_text, minute_text = time_of_day.split(":", maxsplit=1)
                    hour, minute = int(hour_text), int(minute_text)
                except ValueError:
                    break
                if not 0 <= hour <= 23 or not 0 <= minute <= 59:
                    break
                local_now = now.astimezone(ZoneInfo(workflow.timezone))
                next_run_at = local_now.replace(
                    hour=hour, minute=minute, second=0, microsecond=0
                )
                if next_run_at <= local_now:
                    next_run_at += timedelta(days=1)
                return next_run_at
        raise ValueError("medication workflow is missing time_of_day")
    if workflow.template_key == "smart_departure":
        return initial_departure_run_at(workflow)
    raise ValueError(f"unsupported workflow template: {workflow.template_key}")


def _response_for_draft(draft: WorkflowDraft) -> Response:
    return Response(
        {
            "id": str(draft.id),
            "status": draft.status,
            "expires_at": draft.expires_at.isoformat(),
            "task": draft.task_spec_json,
            "workflow": draft.workflow_spec_json,
            "policy": draft.policy_json,
        },
        status=status.HTTP_201_CREATED,
    )


class WorkflowDraftListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateWorkflowDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        now = timezone.now()
        task = WorkflowTaskParser().parse(
            serializer.validated_data["text"], now=now, timezone="Asia/Shanghai"
        )
        if task.ambiguities:
            workflow_json = {}
            policy_json = _clarification_policy(task)
        else:
            try:
                workflow = WorkflowCompiler().compile(task)
            except WorkflowCompileError as exc:
                return Response({"code": exc.code}, status=status.HTTP_400_BAD_REQUEST)
            policy_json = _policy_json(
                evaluate(request.user, task, workflow, now, WORKFLOW_SCOPE)
            )
            workflow_json = workflow.model_dump(mode="json")

        draft = WorkflowDraft.objects.create(
            user=request.user,
            task_spec_json=task.model_dump(mode="json"),
            workflow_spec_json=workflow_json,
            policy_json=policy_json,
            expires_at=now + timedelta(minutes=30),
        )
        return _response_for_draft(draft)


class WorkflowDraftConfirmView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, draft_id):
        serializer = ConfirmWorkflowDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            try:
                draft = WorkflowDraft.objects.select_for_update().get(
                    id=draft_id, user=request.user
                )
            except WorkflowDraft.DoesNotExist:
                return Response(
                    {"detail": "未找到该工作流草稿"},
                    status=status.HTTP_404_NOT_FOUND,
                )

            existing_rule = ReminderRule.objects.filter(workflow_draft=draft).first()
            if existing_rule is not None:
                return Response(
                    {"reminder_id": str(existing_rule.id), "status": "confirmed"},
                    status=status.HTTP_200_OK,
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
                    {"code": "workflow_draft_invalid"}, status=status.HTTP_409_CONFLICT
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
            try:
                next_run_at = _initial_next_run_at(workflow, now)
            except ValueError:
                return Response(
                    {"code": "workflow_draft_invalid"},
                    status=status.HTTP_409_CONFLICT,
                )

            decision = evaluate(request.user, task, workflow, now, WORKFLOW_SCOPE)
            if decision.decision == "needs_clarification":
                return Response(
                    {"code": "workflow_needs_clarification"},
                    status=status.HTTP_409_CONFLICT,
                )

            rule = ReminderRule.objects.create(
                owner=request.user,
                title=task.title,
                timezone=workflow.timezone,
                schedule_json={},
                conditions_json={},
                severity="notification",
                scheduled_at=None,
                template_key=workflow.template_key,
                template_version=workflow.template_version,
                schema_version=workflow.schema_version,
                workflow_spec_json=workflow.model_dump(mode="json"),
                next_run_at=next_run_at,
                source_draft=None,
                workflow_draft=draft,
            )
            if (
                decision.risk_level == "R1"
                and decision.decision == "needs_confirmation"
            ):
                grant = TrustGrant.objects.filter(
                    user=request.user,
                    capability_signature=decision.capability_signature,
                    template_key=workflow.template_key,
                    template_major_version=int(
                        workflow.template_version.split(".", 1)[0]
                    ),
                    status=TrustGrant.Status.ACTIVE,
                ).first()
                if grant is None:
                    TrustGrant.objects.create(
                        user=request.user,
                        capability_signature=decision.capability_signature,
                        template_key=workflow.template_key,
                        template_major_version=int(
                            workflow.template_version.split(".", 1)[0]
                        ),
                        scope_json=WORKFLOW_SCOPE,
                        status=TrustGrant.Status.ACTIVE,
                        expires_at=now + timedelta(days=90),
                    )
                else:
                    grant.scope_json = WORKFLOW_SCOPE
                    grant.expires_at = now + timedelta(days=90)
                    grant.revoked_at = None
                    grant.save(update_fields=["scope_json", "expires_at", "revoked_at"])
            draft.status = WorkflowDraft.Status.CONFIRMED
            draft.confirmed_at = now
            draft.save(update_fields=["status", "confirmed_at"])

        return Response(
            {"reminder_id": str(rule.id), "status": "confirmed"},
            status=status.HTTP_201_CREATED,
        )

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reminders.domain.schemas import ReminderDraftData
from apps.reminders.domain.intent_parser import ReminderIntentParser
from apps.reminders.models import ReminderDraft, ReminderRule
from apps.reminders.providers.deepseek import DeepSeekReminderIntentProvider
from apps.reminders.services.draft_service import create_reminder_draft

from .serializers import CreateTextReminderDraftSerializer, CreateVoiceReminderDraftSerializer


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
    draft = created.draft
    return Response(
        {
            "id": str(draft.id),
            "status": draft.status,
            "expires_at": draft.expires_at.isoformat(),
            "parser_source": created.parser_source,
            "draft": draft.draft_json,
        },
        status=status.HTTP_201_CREATED,
    )


class ReminderDraftListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateTextReminderDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return _create_draft_response(
            request=request,
            text=serializer.validated_data["text"],
        )


class VoiceReminderDraftListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateVoiceReminderDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return _create_draft_response(
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
                source_draft=draft,
            )
            draft.status = "confirmed"
            draft.confirmed_at = timezone.now()
            draft.save(update_fields=["status", "confirmed_at"])

        return Response(
            {"reminder_id": str(rule.id), "status": "confirmed"},
            status=status.HTTP_201_CREATED,
        )

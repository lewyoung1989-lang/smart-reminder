import hashlib
from datetime import timedelta

from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reminders.domain.schemas import ReminderDraftData
from apps.reminders.domain.voice_parser import parse_voice_reminder
from apps.reminders.models import ReminderDraft, ReminderRule, VoiceParseSession

from .serializers import CreateVoiceReminderDraftSerializer


class VoiceReminderDraftListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateVoiceReminderDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        transcript = serializer.validated_data["transcript"]
        expires_at = timezone.now() + timedelta(minutes=15)
        draft_data = parse_voice_reminder(
            transcript,
            now=timezone.now(),
            timezone="Asia/Shanghai",
        )
        draft_json = draft_data.model_dump(mode="json")

        with transaction.atomic():
            session = VoiceParseSession.objects.create(
                user=request.user,
                transcript_sha256=hashlib.sha256(transcript.encode("utf-8")).hexdigest(),
                expires_at=expires_at,
            )
            draft = ReminderDraft.objects.create(
                session=session,
                draft_json=draft_json,
                ambiguities_json=draft_data.ambiguities,
                expires_at=expires_at,
            )

        return Response(
            {
                "id": str(draft.id),
                "status": draft.status,
                "expires_at": draft.expires_at.isoformat(),
                "draft": draft_json,
            },
            status=status.HTTP_201_CREATED,
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

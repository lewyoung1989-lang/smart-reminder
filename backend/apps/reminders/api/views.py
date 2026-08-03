import hashlib
from datetime import timedelta

from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reminders.domain.voice_parser import parse_voice_reminder
from apps.reminders.models import ReminderDraft, VoiceParseSession

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

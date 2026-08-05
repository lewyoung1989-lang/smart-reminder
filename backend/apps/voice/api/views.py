import math
from functools import lru_cache
from uuid import uuid4

from django.conf import settings
from redis.exceptions import RedisError
from rest_framework import status
from rest_framework.exceptions import Throttled
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.voice.domain.audio import AudioValidationError
from apps.voice.domain.results import (
    AsrResponseError,
    AsrTimeoutError,
    AsrUnavailableError,
    EmptyTranscriptError,
)
from apps.voice.providers.funasr import FunAsrProvider
from apps.voice.services.lease import RedisLeaseManager
from apps.voice.services.transcription import AsrBusyError, TranscriptionService

from .serializers import VoiceTranscriptionSerializer
from .throttles import VoiceTranscriptionIpThrottle, VoiceTranscriptionUserThrottle


@lru_cache(maxsize=1)
def build_transcription_service():
    return TranscriptionService(
        provider=FunAsrProvider(
            base_url=settings.ASR_BASE_URL,
            model=settings.ASR_MODEL,
            timeout_seconds=settings.ASR_TIMEOUT_SECONDS,
        ),
        lease_manager=RedisLeaseManager.from_url(
            settings.ASR_REDIS_URL,
            ttl_seconds=settings.ASR_LEASE_TTL_SECONDS,
        ),
    )


def error_response(code, http_status, *, retry_after=None):
    response = Response({"code": code}, status=http_status)
    if retry_after is not None:
        response["Retry-After"] = str(retry_after)
    return response


class VoiceTranscriptionView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]
    throttle_classes = [
        VoiceTranscriptionUserThrottle,
        VoiceTranscriptionIpThrottle,
    ]

    def handle_exception(self, exc):
        if isinstance(exc, Throttled):
            retry_after = math.ceil(exc.wait) if exc.wait is not None else None
            return error_response(
                "rate_limited",
                status.HTTP_429_TOO_MANY_REQUESTS,
                retry_after=retry_after,
            )
        return super().handle_exception(exc)

    def post(self, request):
        audio = request.FILES.get("audio")
        try:
            serializer = VoiceTranscriptionSerializer(data=request.data)
            if not serializer.is_valid():
                errors = serializer.errors.get("audio", [])
                code = errors[0].code if errors else "microphone_audio_invalid"
                if code in {"required", "empty", "invalid"}:
                    code = "microphone_audio_invalid"
                return error_response(code, status.HTTP_400_BAD_REQUEST)

            audio = serializer.validated_data["audio"]
            request_id = str(uuid4())
            outcome = build_transcription_service().transcribe(
                audio,
                user_key=str(request.user.pk),
                request_id=request_id,
            )
            return Response(
                {
                    "request_id": request_id,
                    "status": "completed",
                    "transcript": outcome.result.transcript,
                    "audio_duration_ms": outcome.audio_metadata.duration_ms,
                    "transcription_latency_ms": outcome.result.latency_ms,
                    "provider": outcome.result.provider,
                },
                status=status.HTTP_200_OK,
            )
        except AudioValidationError as exc:
            return error_response(exc.code, status.HTTP_400_BAD_REQUEST)
        except AsrBusyError:
            return error_response(
                "asr_busy",
                status.HTTP_429_TOO_MANY_REQUESTS,
                retry_after=2,
            )
        except EmptyTranscriptError:
            return error_response(
                "empty_transcript",
                status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        except (AsrUnavailableError, RedisError):
            return error_response(
                "asr_unavailable",
                status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        except AsrTimeoutError:
            return error_response(
                "asr_timeout",
                status.HTTP_504_GATEWAY_TIMEOUT,
            )
        except AsrResponseError:
            return error_response(
                "asr_response_invalid",
                status.HTTP_502_BAD_GATEWAY,
            )
        finally:
            if audio is not None:
                audio.close()

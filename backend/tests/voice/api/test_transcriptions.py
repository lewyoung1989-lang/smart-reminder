import io
from uuid import UUID
import wave

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.voice.domain.audio import AudioValidationError, WavMetadata
from apps.voice.domain.results import (
    AsrResponseError,
    AsrResult,
    AsrTimeoutError,
    AsrUnavailableError,
    EmptyTranscriptError,
)
from apps.voice.services.transcription import AsrBusyError, TranscriptionOutcome


URL = "/api/v1/voice/transcriptions"


def wav_upload(*, duration_seconds=0.5, filename="recording.wav"):
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16_000)
        wav.writeframes(b"\x00\x00" * round(duration_seconds * 16_000))
    return SimpleUploadedFile(filename, output.getvalue(), content_type="audio/wav")


class FakeTranscriptionService:
    def __init__(self, *, error=None):
        self.error = error
        self.calls = []

    def transcribe(self, audio, *, user_key, request_id):
        self.calls.append((audio, user_key, request_id))
        if self.error:
            raise self.error
        return TranscriptionOutcome(
            result=AsrResult("明天早上七点提醒我吃药", 321, "funasr"),
            audio_metadata=WavMetadata(16_000, 1, 2, 8_000, 500),
        )


def install_service(monkeypatch, service):
    monkeypatch.setattr(
        "apps.voice.api.views.build_transcription_service",
        lambda: service,
    )


def test_requires_authentication(api_client):
    response = api_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert response.status_code == 401


def test_requires_audio_file(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(URL, {}, format="multipart")

    assert response.status_code == 400
    assert response.json()["code"] == "microphone_audio_invalid"


def test_returns_transcript_and_server_computed_metadata(
    api_client, user, monkeypatch
):
    api_client.force_authenticate(user)
    service = FakeTranscriptionService()
    install_service(monkeypatch, service)
    audio = wav_upload()

    response = api_client.post(URL, {"audio": audio}, format="multipart")

    assert response.status_code == 200
    body = response.json()
    UUID(body["request_id"])
    assert body == {
        "request_id": body["request_id"],
        "status": "completed",
        "transcript": "明天早上七点提醒我吃药",
        "audio_duration_ms": 500,
        "transcription_latency_ms": 321,
        "provider": "funasr",
    }
    assert service.calls[0][1:] == (str(user.pk), body["request_id"])
    assert service.calls[0][0].closed


def test_rejects_oversize_upload_before_service_call(
    api_client, user, monkeypatch, settings
):
    api_client.force_authenticate(user)
    settings.ASR_MAX_AUDIO_BYTES = 10
    service = FakeTranscriptionService()
    install_service(monkeypatch, service)
    audio = wav_upload()

    response = api_client.post(URL, {"audio": audio}, format="multipart")

    assert response.status_code == 400
    assert response.json()["code"] == "audio_too_large"
    assert service.calls == []


def test_maps_audio_validation_error_and_closes_upload(
    api_client, user, monkeypatch
):
    api_client.force_authenticate(user)
    service = FakeTranscriptionService(
        error=AudioValidationError("audio_too_short")
    )
    install_service(monkeypatch, service)
    audio = wav_upload()

    response = api_client.post(URL, {"audio": audio}, format="multipart")

    assert response.status_code == 400
    assert response.json()["code"] == "audio_too_short"
    assert service.calls[0][0].closed


def test_maps_busy_error_with_retry_after(api_client, user, monkeypatch):
    api_client.force_authenticate(user)
    install_service(monkeypatch, FakeTranscriptionService(error=AsrBusyError()))

    response = api_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert response.status_code == 429
    assert response.json()["code"] == "asr_busy"
    assert response.headers["Retry-After"] == "2"


def test_maps_empty_transcript(api_client, user, monkeypatch):
    api_client.force_authenticate(user)
    install_service(
        monkeypatch,
        FakeTranscriptionService(error=EmptyTranscriptError()),
    )

    response = api_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert response.status_code == 422
    assert response.json()["code"] == "empty_transcript"


def test_maps_unavailable_provider(api_client, user, monkeypatch):
    api_client.force_authenticate(user)
    install_service(
        monkeypatch,
        FakeTranscriptionService(error=AsrUnavailableError()),
    )

    response = api_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert response.status_code == 503
    assert response.json()["code"] == "asr_unavailable"


def test_maps_provider_timeout(api_client, user, monkeypatch):
    api_client.force_authenticate(user)
    install_service(
        monkeypatch,
        FakeTranscriptionService(error=AsrTimeoutError()),
    )

    response = api_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert response.status_code == 504
    assert response.json()["code"] == "asr_timeout"


def test_maps_invalid_provider_response(api_client, user, monkeypatch):
    api_client.force_authenticate(user)
    install_service(
        monkeypatch,
        FakeTranscriptionService(error=AsrResponseError()),
    )

    response = api_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert response.status_code == 502
    assert response.json()["code"] == "asr_response_invalid"


def test_enforces_per_user_request_rate(api_client, user, monkeypatch):
    cache.clear()
    api_client.force_authenticate(user)
    install_service(monkeypatch, FakeTranscriptionService())
    monkeypatch.setattr(
        "apps.voice.api.throttles.VoiceTranscriptionUserThrottle.get_rate",
        lambda self: "1/min",
    )

    first = api_client.post(URL, {"audio": wav_upload()}, format="multipart")
    second = api_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["code"] == "rate_limited"


def test_enforces_per_ip_request_rate(user, monkeypatch):
    cache.clear()
    install_service(monkeypatch, FakeTranscriptionService())
    monkeypatch.setattr(
        "apps.voice.api.throttles.VoiceTranscriptionUserThrottle.get_rate",
        lambda self: "100/min",
    )
    monkeypatch.setattr(
        "apps.voice.api.throttles.VoiceTranscriptionIpThrottle.get_rate",
        lambda self: "1/min",
    )
    first_client = APIClient(REMOTE_ADDR="203.0.113.5")
    second_client = APIClient(REMOTE_ADDR="203.0.113.5")
    first_client.force_authenticate(user)
    second_client.force_authenticate(user)

    first = first_client.post(URL, {"audio": wav_upload()}, format="multipart")
    second = second_client.post(URL, {"audio": wav_upload()}, format="multipart")

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["code"] == "rate_limited"

import io
import wave

import pytest

from apps.voice.domain.results import AsrResult
from apps.voice.services.transcription import AsrBusyError, TranscriptionService


def wav_bytes(*, duration_seconds=0.5, sample_rate=16_000):
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(b"\x00\x00" * round(duration_seconds * sample_rate))
    output.seek(0)
    return output


class FakeLease:
    def __init__(self, key):
        self.key = key
        self.released = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.released = True


class FakeLeaseManager:
    def __init__(self, contended_key=None):
        self.contended_key = contended_key
        self.acquired_keys = []
        self.leases = []

    def acquire(self, key):
        self.acquired_keys.append(key)
        if key == self.contended_key:
            return None
        lease = FakeLease(key)
        self.leases.append(lease)
        return lease


class FakeProvider:
    def __init__(self, error=None):
        self.error = error
        self.calls = []

    def transcribe(self, audio, *, request_id):
        self.calls.append((audio, request_id))
        if self.error:
            raise self.error
        return AsrResult("提醒我吃药", 123, "funasr")


def test_validates_audio_acquires_user_and_global_leases_then_transcribes():
    provider = FakeProvider()
    leases = FakeLeaseManager()
    service = TranscriptionService(provider=provider, lease_manager=leases)
    audio = wav_bytes()

    outcome = service.transcribe(audio, user_key="42", request_id="request-1")

    assert outcome.result.transcript == "提醒我吃药"
    assert outcome.audio_metadata.duration_ms == 500
    assert leases.acquired_keys == ["voice:asr:user:42", "voice:asr:global"]
    assert all(lease.released for lease in leases.leases)
    assert provider.calls == [(audio, "request-1")]


@pytest.mark.parametrize(
    "contended_key",
    ["voice:asr:user:42", "voice:asr:global"],
)
def test_rejects_contention_without_calling_provider(contended_key):
    provider = FakeProvider()
    leases = FakeLeaseManager(contended_key=contended_key)
    service = TranscriptionService(provider=provider, lease_manager=leases)

    with pytest.raises(AsrBusyError):
        service.transcribe(wav_bytes(), user_key="42", request_id="request-1")

    assert provider.calls == []
    assert all(lease.released for lease in leases.leases)


def test_releases_both_leases_when_provider_fails():
    provider = FakeProvider(error=RuntimeError("provider failed"))
    leases = FakeLeaseManager()
    service = TranscriptionService(provider=provider, lease_manager=leases)

    with pytest.raises(RuntimeError, match="provider failed"):
        service.transcribe(wav_bytes(), user_key="42", request_id="request-1")

    assert all(lease.released for lease in leases.leases)

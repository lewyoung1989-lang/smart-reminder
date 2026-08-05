from dataclasses import dataclass

from apps.voice.domain.audio import WavMetadata, validate_wav
from apps.voice.domain.results import AsrResult


class AsrBusyError(Exception):
    pass


@dataclass(frozen=True)
class TranscriptionOutcome:
    result: AsrResult
    audio_metadata: WavMetadata


class TranscriptionService:
    def __init__(self, *, provider, lease_manager):
        self.provider = provider
        self.lease_manager = lease_manager

    def transcribe(self, audio, *, user_key, request_id):
        metadata = validate_wav(audio)
        user_lease = self.lease_manager.acquire(f"voice:asr:user:{user_key}")
        if user_lease is None:
            raise AsrBusyError

        with user_lease:
            global_lease = self.lease_manager.acquire("voice:asr:global")
            if global_lease is None:
                raise AsrBusyError

            with global_lease:
                result = self.provider.transcribe(audio, request_id=request_id)

        return TranscriptionOutcome(result=result, audio_metadata=metadata)

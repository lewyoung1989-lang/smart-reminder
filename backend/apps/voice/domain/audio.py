from dataclasses import dataclass
import wave

from django.conf import settings


@dataclass(frozen=True)
class WavMetadata:
    sample_rate: int
    channels: int
    sample_width: int
    frame_count: int
    duration_ms: int


class AudioValidationError(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def validate_wav(audio) -> WavMetadata:
    original_position = audio.tell()
    try:
        audio.seek(0, 2)
        size = audio.tell()
        if size > settings.ASR_MAX_AUDIO_BYTES:
            raise AudioValidationError("audio_too_large")

        audio.seek(0)
        try:
            with wave.open(audio, "rb") as wav:
                channels = wav.getnchannels()
                sample_width = wav.getsampwidth()
                sample_rate = wav.getframerate()
                frame_count = wav.getnframes()
                compression = wav.getcomptype()
        except (EOFError, wave.Error) as error:
            raise AudioValidationError("microphone_audio_invalid") from error

        if (
            compression != "NONE"
            or channels not in (1, 2)
            or sample_width != 2
            or not 8_000 <= sample_rate <= 48_000
        ):
            raise AudioValidationError("microphone_audio_invalid")

        duration_seconds = frame_count / sample_rate
        if duration_seconds < settings.ASR_MIN_DURATION_SECONDS:
            raise AudioValidationError("audio_too_short")
        if duration_seconds > settings.ASR_MAX_DURATION_SECONDS:
            raise AudioValidationError("audio_too_long")

        return WavMetadata(
            sample_rate=sample_rate,
            channels=channels,
            sample_width=sample_width,
            frame_count=frame_count,
            duration_ms=round(duration_seconds * 1000),
        )
    except (AttributeError, OSError) as error:
        raise AudioValidationError("microphone_audio_invalid") from error
    finally:
        audio.seek(original_position)

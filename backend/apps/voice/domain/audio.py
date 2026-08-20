from dataclasses import dataclass

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


PCM_FORMAT = 0x0001
EXTENSIBLE_FORMAT = 0xFFFE
PCM_SUBFORMAT_GUID = bytes.fromhex("0100000000001000800000aa00389b71")


def validate_wav(audio) -> WavMetadata:
    original_position = audio.tell()
    try:
        audio.seek(0, 2)
        size = audio.tell()
        if size > settings.ASR_MAX_AUDIO_BYTES:
            raise AudioValidationError("audio_too_large")

        audio.seek(0)
        channels, sample_width, sample_rate, frame_count = _read_wav_metadata(
            audio.read()
        )

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


def _read_wav_metadata(payload: bytes):
    if len(payload) < 44 or payload[:4] != b"RIFF" or payload[8:12] != b"WAVE":
        raise AudioValidationError("microphone_audio_invalid")

    fmt_chunk = None
    data_size = None
    offset = 12
    while offset + 8 <= len(payload):
        chunk_id = payload[offset : offset + 4]
        chunk_size = int.from_bytes(payload[offset + 4 : offset + 8], "little")
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        if chunk_end > len(payload):
            raise AudioValidationError("microphone_audio_invalid")
        if chunk_id == b"fmt ":
            fmt_chunk = payload[chunk_start:chunk_end]
        elif chunk_id == b"data":
            data_size = chunk_size
        offset = chunk_end + (chunk_size % 2)

    if fmt_chunk is None or data_size is None or len(fmt_chunk) < 16:
        raise AudioValidationError("microphone_audio_invalid")

    audio_format = int.from_bytes(fmt_chunk[0:2], "little")
    channels = int.from_bytes(fmt_chunk[2:4], "little")
    sample_rate = int.from_bytes(fmt_chunk[4:8], "little")
    block_align = int.from_bytes(fmt_chunk[12:14], "little")
    bits_per_sample = int.from_bytes(fmt_chunk[14:16], "little")

    is_pcm = audio_format == PCM_FORMAT
    if audio_format == EXTENSIBLE_FORMAT:
        is_pcm = len(fmt_chunk) >= 40 and fmt_chunk[24:40] == PCM_SUBFORMAT_GUID
    if (
        not is_pcm
        or channels not in (1, 2)
        or bits_per_sample != 16
        or block_align != channels * 2
        or not 8_000 <= sample_rate <= 48_000
    ):
        raise AudioValidationError("microphone_audio_invalid")

    return channels, 2, sample_rate, data_size // block_align

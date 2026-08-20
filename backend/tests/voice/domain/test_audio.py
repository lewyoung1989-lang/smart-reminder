import io
import wave

import pytest

from apps.voice.domain.audio import AudioValidationError, validate_wav


def make_wav(
    *,
    sample_rate: int = 16_000,
    channels: int = 1,
    sample_width: int = 2,
    duration_seconds: float = 0.5,
) -> io.BytesIO:
    output = io.BytesIO()
    frame_count = round(sample_rate * duration_seconds)
    with wave.open(output, "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(sample_width)
        wav.setframerate(sample_rate)
        wav.writeframes(b"\0" * frame_count * channels * sample_width)
    output.seek(0)
    return output


def make_extensible_pcm_wav() -> io.BytesIO:
    sample_rate = 16_000
    channels = 1
    sample_width = 2
    data = b"\0" * (sample_rate * channels * sample_width // 2)
    block_align = channels * sample_width
    fmt = b"".join(
        [
            (0xFFFE).to_bytes(2, "little"),
            channels.to_bytes(2, "little"),
            sample_rate.to_bytes(4, "little"),
            (sample_rate * block_align).to_bytes(4, "little"),
            block_align.to_bytes(2, "little"),
            (sample_width * 8).to_bytes(2, "little"),
            (22).to_bytes(2, "little"),
            (sample_width * 8).to_bytes(2, "little"),
            (0).to_bytes(4, "little"),
            bytes.fromhex("0100000000001000800000aa00389b71"),
        ]
    )
    payload = b"".join(
        [
            b"RIFF",
            (4 + 8 + len(fmt) + 8 + len(data)).to_bytes(4, "little"),
            b"WAVE",
            b"fmt ",
            len(fmt).to_bytes(4, "little"),
            fmt,
            b"data",
            len(data).to_bytes(4, "little"),
            data,
        ]
    )
    return io.BytesIO(payload)


@pytest.mark.parametrize("sample_rate", [8_000, 16_000, 44_100, 48_000])
@pytest.mark.parametrize("channels", [1, 2])
def test_accepts_supported_pcm_wav(sample_rate, channels):
    audio = make_wav(sample_rate=sample_rate, channels=channels)

    metadata = validate_wav(audio)

    assert metadata.sample_rate == sample_rate
    assert metadata.channels == channels
    assert metadata.sample_width == 2
    assert metadata.frame_count == sample_rate // 2
    assert metadata.duration_ms == 500


def test_accepts_extensible_pcm_wav_from_platform_recorders():
    metadata = validate_wav(make_extensible_pcm_wav())

    assert metadata.sample_rate == 16_000
    assert metadata.channels == 1
    assert metadata.sample_width == 2
    assert metadata.duration_ms == 500


def test_restores_stream_position_after_inspection():
    audio = make_wav()
    audio.seek(7)

    validate_wav(audio)

    assert audio.tell() == 7


@pytest.mark.parametrize(
    ("audio", "expected_code"),
    [
        (io.BytesIO(b"not-a-wav"), "microphone_audio_invalid"),
        (make_wav(sample_width=1), "microphone_audio_invalid"),
        (make_wav(sample_rate=7_999), "microphone_audio_invalid"),
        (make_wav(sample_rate=48_001), "microphone_audio_invalid"),
        (make_wav(duration_seconds=0.2), "audio_too_short"),
        (make_wav(duration_seconds=60.1), "audio_too_long"),
    ],
)
def test_rejects_invalid_wav(audio, expected_code):
    with pytest.raises(AudioValidationError) as captured:
        validate_wav(audio)

    assert captured.value.code == expected_code


def test_rejects_audio_above_file_size_limit_before_parsing():
    audio = io.BytesIO(b"R" * (4 * 1024 * 1024 + 1))

    with pytest.raises(AudioValidationError) as captured:
        validate_wav(audio)

    assert captured.value.code == "audio_too_large"

import io
import wave

import numpy as np
import pytest

from services.funasr.app.audio import AudioInputError, normalize_wav


def wav_bytes(*, sample_rate, channels, duration_seconds=0.5):
    frame_count = round(sample_rate * duration_seconds)
    samples = np.full((frame_count, channels), 8192, dtype="<i2")
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(samples.tobytes())
    return output.getvalue()


def numpy_tensor(samples):
    return samples[np.newaxis, :]


def numpy_resample(tensor, original_rate, target_rate):
    target_size = round(tensor.shape[-1] * target_rate / original_rate)
    original_x = np.linspace(0, 1, tensor.shape[-1], endpoint=False)
    target_x = np.linspace(0, 1, target_size, endpoint=False)
    return np.interp(target_x, original_x, tensor[0]).astype(np.float32)[
        np.newaxis, :
    ]


@pytest.mark.parametrize(("sample_rate", "channels"), [(44_100, 1), (48_000, 2)])
def test_normalizes_pcm_wav_to_float32_16khz_mono_tensor(sample_rate, channels):
    normalized = normalize_wav(
        wav_bytes(sample_rate=sample_rate, channels=channels),
        tensor_factory=numpy_tensor,
        resample_fn=numpy_resample,
    )

    assert normalized.sample_rate == 16_000
    assert normalized.tensor.shape == (1, 8_000)
    assert normalized.tensor.dtype == np.float32
    assert np.allclose(normalized.tensor.mean(), 0.25, atol=0.01)


@pytest.mark.parametrize("payload", [b"not-wav", b""])
def test_rejects_invalid_audio(payload):
    with pytest.raises(AudioInputError) as error:
        normalize_wav(
            payload,
            tensor_factory=numpy_tensor,
            resample_fn=numpy_resample,
        )

    assert error.value.code == "microphone_audio_invalid"

from dataclasses import dataclass
from io import BytesIO

import numpy as np
import soundfile as sf


TARGET_SAMPLE_RATE = 16_000


class AudioInputError(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class NormalizedAudio:
    tensor: object
    sample_rate: int


def _torch_tensor(samples):
    import torch

    return torch.from_numpy(samples).unsqueeze(0)


def _torchaudio_resample(tensor, original_rate, target_rate):
    from torchaudio.functional import resample

    return resample(tensor, original_rate, target_rate)


def normalize_wav(payload, *, tensor_factory=None, resample_fn=None):
    tensor_factory = tensor_factory or _torch_tensor
    resample_fn = resample_fn or _torchaudio_resample
    try:
        with sf.SoundFile(BytesIO(payload)) as audio_file:
            if (
                audio_file.format != "WAV"
                or audio_file.subtype != "PCM_16"
                or audio_file.channels not in (1, 2)
                or not 8_000 <= audio_file.samplerate <= 48_000
            ):
                raise AudioInputError("microphone_audio_invalid")
            duration_seconds = len(audio_file) / audio_file.samplerate
            if duration_seconds < 0.3:
                raise AudioInputError("audio_too_short")
            if duration_seconds > 20:
                raise AudioInputError("audio_too_long")
            samples = audio_file.read(dtype="float32", always_2d=True)
            sample_rate = audio_file.samplerate
    except AudioInputError:
        raise
    except (OSError, RuntimeError, TypeError, ValueError, sf.LibsndfileError) as exc:
        raise AudioInputError("microphone_audio_invalid") from exc

    mono = samples.mean(axis=1, dtype=np.float32).astype(np.float32, copy=False)
    tensor = tensor_factory(mono)
    if sample_rate != TARGET_SAMPLE_RATE:
        tensor = resample_fn(tensor, sample_rate, TARGET_SAMPLE_RATE)
    return NormalizedAudio(tensor=tensor, sample_rate=TARGET_SAMPLE_RATE)

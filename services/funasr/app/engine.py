import os
from pathlib import Path


MODEL_CACHE_DIR = Path(os.environ.get("MODELSCOPE_CACHE", "/models"))


def _cached_model_path(model_id: str) -> str:
    direct_path = MODEL_CACHE_DIR / model_id
    if direct_path.exists():
        return str(direct_path)
    return str(MODEL_CACHE_DIR / "models" / model_id)


MODEL_CONFIG = {
    "model": _cached_model_path(
        "iic/speech_seaco_paraformer_large_asr_nat-zh-cn-16k-common-vocab8404-pytorch"
    ),
    "model_revision": "v2.0.4",
    "vad_model": _cached_model_path(
        "iic/speech_fsmn_vad_zh-cn-16k-common-pytorch"
    ),
    "vad_model_revision": "v2.0.4",
    "punc_model": _cached_model_path(
        "iic/punc_ct-transformer_zh-cn-common-vocab272727-pytorch"
    ),
    "punc_model_revision": "v2.0.4",
    "device": "cpu",
    "disable_update": True,
}


class FunAsrEngine:
    def __init__(self, model_factory=None):
        self._model_factory = model_factory
        self._model = None
        self.ready = False

    def load(self):
        if self._model is not None:
            return
        if self._model_factory is None:
            from funasr import AutoModel

            self._model_factory = AutoModel
        self._model = self._model_factory(**MODEL_CONFIG)
        self.ready = True

    def transcribe(self, tensor):
        model_input = tensor
        if hasattr(tensor, "detach"):
            model_input = tensor.squeeze(0).detach().cpu().numpy()
        result = self._model.generate(input=model_input)
        if not isinstance(result, list) or not result:
            return ""
        first = result[0]
        if not isinstance(first, dict) or not isinstance(first.get("text"), str):
            return ""
        return first["text"]

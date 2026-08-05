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
        self._model = self._model_factory(
            model="paraformer-zh",
            vad_model="fsmn-vad",
            punc_model="ct-punc",
            device="cpu",
            disable_update=True,
        )
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

from services.funasr.app.engine import FunAsrEngine


class FakeModel:
    def __init__(self):
        self.calls = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        return [{"text": "提醒我吃药"}]


def test_loads_pinned_model_stack_once_and_extracts_text():
    created = []
    model = FakeModel()

    def factory(**kwargs):
        created.append(kwargs)
        return model

    engine = FunAsrEngine(model_factory=factory)

    engine.load()
    engine.load()
    transcript = engine.transcribe("tensor")

    assert engine.ready
    assert created == [
        {
            "model": "paraformer-zh",
            "model_revision": "v2.0.4",
            "vad_model": "fsmn-vad",
            "vad_model_revision": "v2.0.4",
            "punc_model": "ct-punc",
            "punc_model_revision": "v2.0.4",
            "device": "cpu",
            "disable_update": True,
        }
    ]
    assert model.calls == [{"input": "tensor"}]
    assert transcript == "提醒我吃药"

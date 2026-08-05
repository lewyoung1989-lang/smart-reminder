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
            "vad_model": "fsmn-vad",
            "punc_model": "ct-punc",
            "device": "cpu",
            "disable_update": True,
        }
    ]
    assert model.calls == [{"input": "tensor"}]
    assert transcript == "提醒我吃药"

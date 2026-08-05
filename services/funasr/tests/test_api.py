from fastapi.testclient import TestClient

from services.funasr.app.audio import AudioInputError, NormalizedAudio
from services.funasr.app.main import create_app


class FakeEngine:
    def __init__(self, *, transcript="提醒我吃药", ready=False):
        self.transcript = transcript
        self.ready = ready
        self.calls = []

    def load(self):
        self.ready = True

    def transcribe(self, tensor):
        self.calls.append(tensor)
        return self.transcript


def successful_normalizer(payload):
    return NormalizedAudio(tensor="normalized-tensor", sample_rate=16_000)


def test_health_reflects_engine_readiness():
    engine = FakeEngine(ready=False)
    client = TestClient(
        create_app(engine=engine, normalizer=successful_normalizer, load_on_startup=False)
    )

    assert client.get("/health").status_code == 503
    engine.ready = True
    assert client.get("/health").json() == {"status": "ok", "ready": True}


def test_transcribes_with_openai_compatible_contract():
    engine = FakeEngine(transcript="  明天早上提醒我吃药。  ", ready=True)
    client = TestClient(
        create_app(engine=engine, normalizer=successful_normalizer, load_on_startup=False)
    )

    response = client.post(
        "/v1/audio/transcriptions",
        files={"file": ("recording.wav", b"wav", "audio/wav")},
        data={"model": "paraformer-zh", "response_format": "json"},
    )

    assert response.status_code == 200
    assert response.json() == {"text": "明天早上提醒我吃药。"}
    assert engine.calls == ["normalized-tensor"]


def test_rejects_oversize_upload_before_normalization():
    called = []
    client = TestClient(
        create_app(
            engine=FakeEngine(ready=True),
            normalizer=lambda payload: called.append(payload),
            load_on_startup=False,
            max_audio_bytes=3,
        )
    )

    response = client.post(
        "/v1/audio/transcriptions",
        files={"file": ("recording.wav", b"four", "audio/wav")},
        data={"model": "paraformer-zh", "response_format": "json"},
    )

    assert response.status_code == 413
    assert response.json()["detail"]["code"] == "audio_too_large"
    assert called == []


def test_rejects_invalid_audio():
    def invalid_normalizer(payload):
        raise AudioInputError("microphone_audio_invalid")

    client = TestClient(
        create_app(
            engine=FakeEngine(ready=True),
            normalizer=invalid_normalizer,
            load_on_startup=False,
        )
    )

    response = client.post(
        "/v1/audio/transcriptions",
        files={"file": ("recording.wav", b"invalid", "audio/wav")},
        data={"model": "paraformer-zh", "response_format": "json"},
    )

    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "microphone_audio_invalid"


def test_rejects_blank_engine_output():
    client = TestClient(
        create_app(
            engine=FakeEngine(transcript="   ", ready=True),
            normalizer=successful_normalizer,
            load_on_startup=False,
        )
    )

    response = client.post(
        "/v1/audio/transcriptions",
        files={"file": ("recording.wav", b"wav", "audio/wav")},
        data={"model": "paraformer-zh", "response_format": "json"},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "empty_transcript"

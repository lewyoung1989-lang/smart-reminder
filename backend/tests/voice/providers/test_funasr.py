import io

import httpx
import pytest

from apps.voice.domain.results import (
    AsrBusyError,
    AsrResponseError,
    AsrTimeoutError,
    AsrUnavailableError,
    EmptyTranscriptError,
)
from apps.voice.providers.funasr import (
    FunAsrProvider,
    HttpxAudioTransport,
    TransportResponse,
)


class FakeTransport:
    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error
        self.calls = []

    def post_audio(self, url, *, audio, model, timeout_seconds):
        self.calls.append(
            {
                "url": url,
                "audio": audio,
                "model": model,
                "timeout_seconds": timeout_seconds,
            }
        )
        if self.error is not None:
            raise self.error
        return self.response


def test_transcribes_with_private_openai_compatible_endpoint():
    transport = FakeTransport(
        TransportResponse(payload={"text": "  明天早上七点提醒我吃药。  "}, latency_ms=321)
    )
    audio = io.BytesIO(b"wav")
    provider = FunAsrProvider(
        base_url="http://funasr:8000/",
        model="paraformer-zh",
        timeout_seconds=20,
        transport=transport,
    )

    result = provider.transcribe(audio, request_id="request-1")

    assert result.transcript == "明天早上七点提醒我吃药。"
    assert result.latency_ms == 321
    assert result.provider == "funasr"
    assert transport.calls == [
        {
            "url": "http://funasr:8000/v1/audio/transcriptions",
            "audio": audio,
            "model": "paraformer-zh",
            "timeout_seconds": 20,
        }
    ]


@pytest.mark.parametrize("payload", [{}, {"text": 3}, {"unexpected": "value"}])
def test_rejects_invalid_provider_response(payload):
    provider = FunAsrProvider(transport=FakeTransport(TransportResponse(payload, 2)))

    with pytest.raises(AsrResponseError):
        provider.transcribe(io.BytesIO(b"wav"), request_id="request-1")


def test_rejects_blank_transcript():
    provider = FunAsrProvider(
        transport=FakeTransport(TransportResponse({"text": "   "}, 2))
    )

    with pytest.raises(EmptyTranscriptError):
        provider.transcribe(io.BytesIO(b"wav"), request_id="request-1")


def test_rejects_transcript_over_500_characters():
    provider = FunAsrProvider(
        transport=FakeTransport(TransportResponse({"text": "字" * 501}, 2))
    )

    with pytest.raises(AsrResponseError):
        provider.transcribe(io.BytesIO(b"wav"), request_id="request-1")


@pytest.mark.parametrize("error", [AsrUnavailableError(), AsrTimeoutError()])
def test_preserves_stable_transport_errors(error):
    provider = FunAsrProvider(transport=FakeTransport(error=error))

    with pytest.raises(type(error)):
        provider.transcribe(io.BytesIO(b"wav"), request_id="request-1")


def test_http_transport_posts_openai_compatible_multipart_request():
    def handler(request):
        body = request.read()
        assert request.method == "POST"
        assert str(request.url) == "http://funasr:8000/v1/audio/transcriptions"
        assert request.headers["content-type"].startswith("multipart/form-data;")
        assert b'name="file"; filename="audio.wav"' in body
        assert b"Content-Type: audio/wav" in body
        assert b'name="model"' in body
        assert b"paraformer-zh" in body
        assert b'name="response_format"' in body
        assert b"json" in body
        return httpx.Response(200, json={"text": "test"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    transport = HttpxAudioTransport(client=client)

    response = transport.post_audio(
        "http://funasr:8000/v1/audio/transcriptions",
        audio=io.BytesIO(b"wav"),
        model="paraformer-zh",
        timeout_seconds=20,
    )

    assert response.payload == {"text": "test"}
    assert response.latency_ms >= 0


@pytest.mark.parametrize(
    ("transport_error", "expected_error"),
    [
        (httpx.ReadTimeout("slow"), AsrTimeoutError),
        (httpx.ConnectError("offline"), AsrUnavailableError),
    ],
)
def test_http_transport_maps_network_errors(transport_error, expected_error):
    def handler(request):
        transport_error.request = request
        raise transport_error

    client = httpx.Client(transport=httpx.MockTransport(handler))
    transport = HttpxAudioTransport(client=client)

    with pytest.raises(expected_error):
        transport.post_audio(
            "http://funasr:8000/v1/audio/transcriptions",
            audio=io.BytesIO(b"wav"),
            model="paraformer-zh",
            timeout_seconds=20,
        )


def test_http_transport_rejects_non_json_response():
    client = httpx.Client(
        transport=httpx.MockTransport(
            lambda request: httpx.Response(200, content=b"not-json")
        )
    )
    transport = HttpxAudioTransport(client=client)

    with pytest.raises(AsrResponseError):
        transport.post_audio(
            "http://funasr:8000/v1/audio/transcriptions",
            audio=io.BytesIO(b"wav"),
            model="paraformer-zh",
            timeout_seconds=20,
        )


def test_http_transport_preserves_upstream_busy_signal():
    client = httpx.Client(
        transport=httpx.MockTransport(
            lambda request: httpx.Response(429, json={"detail": {"code": "asr_busy"}})
        )
    )
    transport = HttpxAudioTransport(client=client)

    with pytest.raises(AsrBusyError):
        transport.post_audio(
            "http://funasr:8000/v1/audio/transcriptions",
            audio=io.BytesIO(b"wav"),
            model="paraformer-zh",
            timeout_seconds=20,
        )

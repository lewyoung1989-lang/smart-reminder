from dataclasses import dataclass
from time import monotonic

import httpx

from apps.voice.domain.results import (
    AsrResponseError,
    AsrResult,
    AsrTimeoutError,
    AsrUnavailableError,
    EmptyTranscriptError,
)


@dataclass(frozen=True)
class TransportResponse:
    payload: object
    latency_ms: int


class HttpxAudioTransport:
    def __init__(self, client=None):
        self.client = client or httpx.Client()
        self._owns_client = client is None

    def post_audio(self, url, *, audio, model, timeout_seconds):
        started_at = monotonic()
        try:
            response = self.client.post(
                url,
                files={"file": ("audio.wav", audio, "audio/wav")},
                data={"model": model, "response_format": "json"},
                timeout=timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
        except httpx.TimeoutException as exc:
            raise AsrTimeoutError from exc
        except httpx.RequestError as exc:
            raise AsrUnavailableError from exc
        except (httpx.HTTPStatusError, ValueError) as exc:
            raise AsrResponseError from exc

        return TransportResponse(
            payload=payload,
            latency_ms=round((monotonic() - started_at) * 1000),
        )

    def close(self):
        if self._owns_client:
            self.client.close()


class FunAsrProvider:
    def __init__(
        self,
        *,
        base_url="http://localhost:18001",
        model="paraformer-zh",
        timeout_seconds=20,
        transport=None,
    ):
        self.base_url = base_url
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.transport = transport or HttpxAudioTransport()

    def transcribe(self, audio, *, request_id):
        response = self.transport.post_audio(
            f"{self.base_url.rstrip('/')}/v1/audio/transcriptions",
            audio=audio,
            model=self.model,
            timeout_seconds=self.timeout_seconds,
        )
        payload = response.payload
        if not isinstance(payload, dict) or not isinstance(payload.get("text"), str):
            raise AsrResponseError

        transcript = payload["text"].strip()
        if not transcript:
            raise EmptyTranscriptError

        return AsrResult(
            transcript=transcript,
            latency_ms=response.latency_ms,
            provider="funasr",
        )

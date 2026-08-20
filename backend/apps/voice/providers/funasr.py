from dataclasses import dataclass
from time import monotonic

import httpx

from apps.voice.domain.results import (
    AsrBusyError,
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
        timeout = self._build_timeout(timeout_seconds)
        try:
            response = self.client.post(
                url,
                files={"file": ("audio.wav", audio, "audio/wav")},
                data={"model": model, "response_format": "json"},
                timeout=timeout,
                follow_redirects=False,
            )
            elapsed_seconds = monotonic() - started_at
            if elapsed_seconds > timeout_seconds:
                raise AsrTimeoutError
            self._raise_stable_provider_error(response)
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
            latency_ms=round(elapsed_seconds * 1000),
        )

    @staticmethod
    def _build_timeout(timeout_seconds):
        if timeout_seconds < 8:
            raise ValueError("timeout_seconds must be at least 8")
        return httpx.Timeout(
            connect=2,
            pool=1,
            write=4,
            read=timeout_seconds - 7,
        )

    def _raise_stable_provider_error(self, response):
        if response.status_code not in (422, 429, 503, 504):
            return
        try:
            payload = response.json()
        except ValueError:
            return
        detail = payload.get("detail") if isinstance(payload, dict) else None
        code = detail.get("code") if isinstance(detail, dict) else None
        error_type = {
            (422, "empty_transcript"): EmptyTranscriptError,
            (429, "asr_busy"): AsrBusyError,
            (503, "asr_unavailable"): AsrUnavailableError,
            (504, "asr_timeout"): AsrTimeoutError,
        }.get((response.status_code, code))
        if error_type is not None:
            raise error_type

    def close(self):
        if self._owns_client:
            self.client.close()


class FunAsrProvider:
    def __init__(
        self,
        *,
        base_url="http://localhost:18001",
        model="paraformer-zh",
        timeout_seconds=75,
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
        if len(transcript) > 500:
            raise AsrResponseError

        return AsrResult(
            transcript=transcript,
            latency_ms=response.latency_ms,
            provider="funasr",
        )

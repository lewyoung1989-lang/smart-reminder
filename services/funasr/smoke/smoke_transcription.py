#!/usr/bin/env python3
import json
import re
import sys
import unicodedata
import urllib.request
import uuid
from pathlib import Path


EXPECTED_WORDS = ("明天", "提醒", "吃药")


def normalize_transcript(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).replace("藥", "药")
    return re.sub(r"[\W_]+", "", normalized, flags=re.UNICODE)


def assert_expected_transcript(transcript: str) -> None:
    normalized = normalize_transcript(transcript)
    if not all(word in normalized for word in EXPECTED_WORDS):
        raise ValueError("transcript did not contain expected Mandarin words")


def _multipart(audio: bytes) -> tuple[bytes, str]:
    boundary = f"smart-reminder-{uuid.uuid4().hex}"
    chunks = []
    for name, value in (("model", "paraformer-zh"), ("response_format", "json")):
        chunks.append(
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n".encode()
        )
    chunks.extend(
        (
            (
                f"--{boundary}\r\n"
                'Content-Disposition: form-data; name="file"; '
                'filename="mandarin-reminder.wav"\r\n'
                "Content-Type: audio/wav\r\n\r\n"
            ).encode(),
            audio,
            b"\r\n",
            f"--{boundary}--\r\n".encode(),
        )
    )
    return b"".join(chunks), boundary


def transcribe(
    base_url: str, audio_path: Path, timeout_seconds: float = 30
) -> str:
    body, boundary = _multipart(audio_path.read_bytes())
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/v1/audio/transcriptions",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        payload = json.load(response)
    transcript = payload.get("text") if isinstance(payload, dict) else None
    if not isinstance(transcript, str):
        raise ValueError("response did not contain a text string")
    return transcript


def main(arguments=None) -> int:
    arguments = list(sys.argv[1:] if arguments is None else arguments)
    if len(arguments) != 2:
        raise ValueError("usage: smoke_transcription.py BASE_URL AUDIO.wav")
    base_url, audio_path = arguments
    transcript = transcribe(base_url, Path(audio_path), timeout_seconds=30)
    assert_expected_transcript(transcript)
    print("FUNASR_SMOKE_OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        print("FUNASR_SMOKE_FAILED", file=sys.stderr)
        raise SystemExit(1)

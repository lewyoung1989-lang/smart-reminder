import importlib.util
import wave
from pathlib import Path

import pytest


SERVICE_ROOT = Path(__file__).resolve().parents[1]
CLIENT = SERVICE_ROOT / "smoke/smoke_transcription.py"
FIXTURE = SERVICE_ROOT / "smoke/fixtures/mandarin_reminder.wav"


def load_client():
    spec = importlib.util.spec_from_file_location("smoke_transcription", CLIENT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_synthetic_mandarin_fixture_is_short_pcm_wav():
    with wave.open(str(FIXTURE), "rb") as audio:
        duration = audio.getnframes() / audio.getframerate()
        assert audio.getnchannels() == 1
        assert audio.getsampwidth() == 2
        assert audio.getframerate() == 16000
        assert 0.3 <= duration <= 10


def test_smoke_accepts_normalized_expected_mandarin_words():
    client = load_client()

    client.assert_expected_transcript("明 天，提醒 我 吃 藥。")


def test_smoke_rejects_transcript_missing_expected_words():
    client = load_client()

    with pytest.raises(ValueError, match="expected Mandarin words"):
        client.assert_expected_transcript("明天早上七点")


def test_smoke_main_prints_only_fixed_success_message(monkeypatch, capsys):
    client = load_client()
    monkeypatch.setattr(
        client,
        "transcribe",
        lambda base_url, audio_path, timeout_seconds: "明天提醒我吃药",
    )

    assert client.main(["http://funasr:8000", str(FIXTURE)]) == 0
    assert capsys.readouterr().out == "FUNASR_SMOKE_OK\n"

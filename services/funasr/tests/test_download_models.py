import json

import pytest

from services.funasr.app import download_models


class FakeEngine:
    def __init__(self, error=None):
        self.error = error
        self.load_calls = 0

    def load(self):
        self.load_calls += 1
        if self.error:
            raise self.error


def test_check_missing_marker_does_not_load_model(tmp_path):
    engine = FakeEngine(error=AssertionError("must not load"))

    result = download_models.main(
        ["--check"], marker_path=tmp_path / "ready.json", engine=engine
    )

    assert result == 1
    assert engine.load_calls == 0


def test_successful_load_atomically_writes_current_revision_marker(tmp_path):
    marker = tmp_path / "ready.json"
    engine = FakeEngine()

    result = download_models.main([], marker_path=marker, engine=engine)

    assert result == 0
    assert engine.load_calls == 1
    assert json.loads(marker.read_text()) == download_models.READY_MARKER
    assert list(tmp_path.glob("*.tmp")) == []


def test_failed_load_does_not_replace_existing_marker(tmp_path):
    marker = tmp_path / "ready.json"
    marker.write_text('{"revision":"old"}\n')
    engine = FakeEngine(error=RuntimeError("load failed"))

    with pytest.raises(RuntimeError, match="load failed"):
        download_models.main([], marker_path=marker, engine=engine)

    assert marker.read_text() == '{"revision":"old"}\n'


def test_check_rejects_marker_for_old_revision(tmp_path):
    marker = tmp_path / "ready.json"
    old = dict(download_models.READY_MARKER)
    old["model_revision"] = "old"
    marker.write_text(json.dumps(old))

    assert download_models.main(["--check"], marker_path=marker) == 1


def test_check_accepts_exact_current_revision_marker(tmp_path):
    marker = tmp_path / "ready.json"
    marker.write_text(json.dumps(download_models.READY_MARKER))

    assert download_models.main(["--check"], marker_path=marker) == 0

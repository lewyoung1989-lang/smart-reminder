import argparse
import json
import os
from pathlib import Path

from .engine import MODEL_CONFIG, FunAsrEngine


READY_MARKER = {
    "schema_version": 1,
    "model": MODEL_CONFIG["model"],
    "model_revision": MODEL_CONFIG["model_revision"],
    "vad_model": MODEL_CONFIG["vad_model"],
    "vad_model_revision": MODEL_CONFIG["vad_model_revision"],
    "punc_model": MODEL_CONFIG["punc_model"],
    "punc_model_revision": MODEL_CONFIG["punc_model_revision"],
}


def _default_marker_path() -> Path:
    return Path(os.environ.get("MODELSCOPE_CACHE", "/models")) / (
        ".smart-reminder-funasr-ready.json"
    )


def _is_current(marker_path: Path) -> bool:
    try:
        return json.loads(marker_path.read_text()) == READY_MARKER
    except (OSError, ValueError, TypeError):
        return False


def _write_marker(marker_path: Path) -> None:
    temporary = marker_path.with_name(
        f"{marker_path.name}.{os.getpid()}.tmp"
    )
    temporary.write_text(
        json.dumps(READY_MARKER, sort_keys=True, separators=(",", ":"))
        + "\n"
    )
    os.replace(temporary, marker_path)


def main(arguments=None, *, marker_path=None, engine=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args(arguments)
    marker_path = Path(marker_path or _default_marker_path())

    if options.check:
        if _is_current(marker_path):
            print("FUNASR_MODEL_CACHE_READY")
            return 0
        print("FUNASR_MODEL_CACHE_MISSING")
        return 1

    (engine or FunAsrEngine()).load()
    _write_marker(marker_path)
    print("FUNASR_MODEL_CACHE_INITIALIZED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

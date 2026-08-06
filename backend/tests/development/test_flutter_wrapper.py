import os
import plistlib
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
WRAPPER = REPO_ROOT / "scripts/flutterw"
IOS_INFO_PLIST = REPO_ROOT / "app/ios/Runner/Info.plist"


def run(*args, cwd):
    return subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=True,
    )


def test_flutter_wrapper_reuses_sdk_from_main_worktree(tmp_path):
    main = tmp_path / "main"
    worktree = tmp_path / "feature"
    scripts = main / "scripts"
    fake_flutter = main / ".tools/flutter/bin/flutter"
    scripts.mkdir(parents=True)
    fake_flutter.parent.mkdir(parents=True)
    shutil.copy2(WRAPPER, scripts / "flutterw")
    fake_flutter.write_text("#!/bin/sh\nprintf 'flutter:%s\\n' \"$*\"\n")
    fake_flutter.chmod(0o755)

    run("git", "init", "-q", cwd=main)
    run("git", "config", "user.name", "Test User", cwd=main)
    run("git", "config", "user.email", "test@example.com", cwd=main)
    run("git", "add", "scripts/flutterw", cwd=main)
    run("git", "commit", "-qm", "test fixture", cwd=main)
    run("git", "worktree", "add", "--detach", str(worktree), cwd=main)

    result = subprocess.run(
        [str(worktree / "scripts/flutterw"), "doctor"],
        cwd=worktree,
        env={**os.environ, "CI": "true"},
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "flutter:doctor"


def test_ios_declares_camera_usage_description():
    plist = plistlib.loads(IOS_INFO_PLIST.read_bytes())

    assert plist["NSCameraUsageDescription"].strip()

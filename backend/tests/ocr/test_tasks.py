import os
from pathlib import Path
import subprocess
import sys

from celery.exceptions import Retry
import pytest

from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.models import OCRCandidate, OCRJob
from apps.ocr.tasks import process_ocr_job


def test_task_module_does_not_require_cv2_during_api_import():
    backend_root = Path(__file__).resolve().parents[2]
    script = """
import builtins
import os

original_import = builtins.__import__

def guarded_import(name, *args, **kwargs):
    if name == "cv2":
        raise ModuleNotFoundError("cv2 is unavailable in the API image")
    return original_import(name, *args, **kwargs)

builtins.__import__ = guarded_import
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
import django
django.setup()
import apps.ocr.tasks
"""
    env = os.environ.copy()
    env["PYTHONPATH"] = str(backend_root)

    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=backend_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr


@pytest.mark.django_db
def test_process_task_records_success_metadata(user, mocker, caplog):
    job = OCRJob.objects.create(user=user, image_keys={"front": "front"})
    OCRCandidate.objects.create(job=job, raw_line_count=1)
    OCRJob.objects.filter(id=job.id).update(status=OCRJob.Status.SUCCEEDED)
    job.refresh_from_db()
    mocker.patch("apps.ocr.tasks.get_object_storage", return_value=object())
    mocker.patch("apps.ocr.tasks.get_ocr_provider", return_value=object())
    semantic_provider = object()
    mocker.patch(
        "apps.ocr.tasks.get_medicine_semantic_provider",
        return_value=semantic_provider,
    )
    run_job = mocker.patch("apps.ocr.tasks.run_job", return_value=job)

    with caplog.at_level("INFO"):
        process_ocr_job.run(str(job.id))

    assert str(job.id) in caplog.text
    assert "line_count" in caplog.text
    assert run_job.call_args.kwargs["semantic_provider"] is semantic_provider


@pytest.mark.django_db
def test_process_task_marks_retryable_failure_as_queued(user, mocker):
    job = OCRJob.objects.create(user=user, image_keys={"front": "front"})
    mocker.patch("apps.ocr.tasks.get_object_storage", return_value=object())
    mocker.patch("apps.ocr.tasks.get_ocr_provider", return_value=object())
    mocker.patch("apps.ocr.tasks.run_job", side_effect=RuntimeError("failed"))
    mocker.patch.object(process_ocr_job, "retry", side_effect=Retry())

    with pytest.raises(Retry):
        process_ocr_job.run(str(job.id))

    job.refresh_from_db()
    assert job.status == OCRJob.Status.QUEUED
    assert job.error_code == "ocr_retryable_failure"


@pytest.mark.django_db
def test_process_task_marks_terminal_failure_after_retry_limit(
    settings,
    user,
    mocker,
):
    job = OCRJob.objects.create(user=user, image_keys={"front": "front"})
    mocker.patch("apps.ocr.tasks.get_object_storage", return_value=object())
    mocker.patch("apps.ocr.tasks.get_ocr_provider", return_value=object())
    mocker.patch("apps.ocr.tasks.run_job", side_effect=RuntimeError("failed"))

    process_ocr_job.push_request(retries=settings.OCR_MAX_RETRIES)
    try:
        process_ocr_job.run(str(job.id))
    finally:
        process_ocr_job.pop_request()

    job.refresh_from_db()
    assert job.status == OCRJob.Status.FAILED
    assert job.error_code == "ocr_failed"


@pytest.mark.django_db
def test_process_logs_metadata_without_recognized_text(
    user,
    monkeypatch,
    mocker,
    caplog,
):
    sensitive_text = "布洛芬缓释胶囊"
    job = OCRJob.objects.create(user=user, image_keys={"front": "front"})

    class FakeStorage:
        def get_bytes(self, key):
            return b"image"

    class FakeProvider:
        def recognize(self, image_bytes, *, role):
            line = OCRLine(
                ((0, 0), (1, 0), (1, 1), (0, 1)),
                sensitive_text,
                0.96,
            )
            return OCRDocument(role, (line,))

    monkeypatch.setattr(
        "apps.ocr.services.job_runner.prepare_ocr_variants",
        lambda value, role: (value,),
    )
    mocker.patch(
        "apps.ocr.tasks.get_object_storage",
        return_value=FakeStorage(),
    )
    mocker.patch(
        "apps.ocr.tasks.get_ocr_provider",
        return_value=FakeProvider(),
    )

    with caplog.at_level("INFO"):
        process_ocr_job.run(str(job.id))

    assert str(job.id) in caplog.text
    assert "duration_ms" in caplog.text
    assert "line_count=1" in caplog.text
    assert sensitive_text not in caplog.text

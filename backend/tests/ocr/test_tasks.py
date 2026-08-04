from celery.exceptions import Retry
import pytest

from apps.ocr.models import OCRCandidate, OCRJob
from apps.ocr.tasks import process_ocr_job


@pytest.mark.django_db
def test_process_task_records_success_metadata(user, mocker, caplog):
    job = OCRJob.objects.create(user=user, image_keys={"front": "front"})
    OCRCandidate.objects.create(job=job, raw_line_count=1)
    OCRJob.objects.filter(id=job.id).update(status=OCRJob.Status.SUCCEEDED)
    job.refresh_from_db()
    mocker.patch("apps.ocr.tasks.get_object_storage", return_value=object())
    mocker.patch("apps.ocr.tasks.get_ocr_provider", return_value=object())
    mocker.patch("apps.ocr.tasks.run_job", return_value=job)

    with caplog.at_level("INFO"):
        process_ocr_job.run(str(job.id))

    assert str(job.id) in caplog.text
    assert "line_count" in caplog.text


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

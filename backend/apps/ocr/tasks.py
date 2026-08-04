import logging
import time

from celery import shared_task
from django.conf import settings

from apps.ocr.models import OCRJob
from apps.ocr.providers.factory import get_ocr_provider
from apps.ocr.providers.storage import get_object_storage


logger = logging.getLogger(__name__)


def run_job(*args, **kwargs):
    from apps.ocr.services.job_runner import run_job as execute_job

    return execute_job(*args, **kwargs)


@shared_task(bind=True, acks_late=True)
def process_ocr_job(self, job_id):
    started = time.monotonic()
    try:
        job = run_job(
            job_id,
            storage=get_object_storage(),
            provider=get_ocr_provider(),
        )
        line_count = (
            job.candidate.raw_line_count
            if hasattr(job, "candidate")
            else 0
        )
        duration_ms = int((time.monotonic() - started) * 1000)
        # 日志只保留排障元数据，禁止记录完整 OCR 文本、图片和签名地址。
        logger.info(
            "ocr_complete job_id=%s duration_ms=%d line_count=%d provider=%s",
            job_id,
            duration_ms,
            line_count,
            job.provider,
        )
    except Exception as exc:
        job = OCRJob.objects.get(id=job_id)
        if self.request.retries < settings.OCR_MAX_RETRIES:
            # 先恢复为排队状态再抛出 Retry，保证进程退出后仍可观察和重投。
            job.status = OCRJob.Status.QUEUED
            job.error_code = "ocr_retryable_failure"
            job.save(
                update_fields=["status", "error_code", "updated_at"]
            )
            raise self.retry(
                exc=exc,
                countdown=2**self.request.retries,
                max_retries=settings.OCR_MAX_RETRIES,
            )

        job.status = OCRJob.Status.FAILED
        job.error_code = "ocr_failed"
        job.save(update_fields=["status", "error_code", "updated_at"])
        logger.warning(
            "ocr_failed job_id=%s error_code=%s",
            job_id,
            job.error_code,
        )


@shared_task
def delete_ocr_job_images(job_id):
    from apps.ocr.services.retention import delete_job_images

    try:
        return delete_job_images(job_id, storage=get_object_storage())
    except Exception:
        # 日志不记录对象键，删除失败时由数据库中的键支持后续重试。
        logger.exception(
            "image_delete_failed job_id=%s error_code=image_delete_failed",
            job_id,
        )
        raise


@shared_task
def purge_expired_ocr_images():
    from apps.ocr.services.retention import purge_expired_images

    return purge_expired_images(storage=get_object_storage())

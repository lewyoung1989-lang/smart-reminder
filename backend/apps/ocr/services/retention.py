import logging

from django.db import transaction
from django.utils import timezone

from apps.ocr.models import OCRJob


logger = logging.getLogger(__name__)


def delete_job_images(job_id, *, storage):
    job = OCRJob.objects.get(id=job_id)
    # 只有全部对象删除成功后才清空键；中途失败时保留键供下次重试。
    for key in job.image_keys.values():
        storage.delete(key)

    with transaction.atomic():
        locked = OCRJob.objects.select_for_update().get(id=job_id)
        locked.image_keys = {}
        locked.save(update_fields=["image_keys", "updated_at"])


def purge_expired_images(*, storage):
    job_ids = list(
        OCRJob.objects.filter(expires_at__lte=timezone.now())
        .exclude(image_keys={})
        .order_by("created_at")
        .values_list("id", flat=True)
    )
    deleted = 0
    for job_id in job_ids:
        try:
            delete_job_images(job_id, storage=storage)
        except Exception:
            logger.warning(
                "image_delete_failed job_id=%s error_code=image_delete_failed",
                job_id,
            )
            continue
        deleted += 1
    return deleted

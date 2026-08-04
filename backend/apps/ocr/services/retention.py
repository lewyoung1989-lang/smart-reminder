from django.db import transaction
from django.utils import timezone

from apps.ocr.models import OCRJob


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
        .values_list("id", flat=True)
    )
    for job_id in job_ids:
        delete_job_images(job_id, storage=storage)
    return len(job_ids)

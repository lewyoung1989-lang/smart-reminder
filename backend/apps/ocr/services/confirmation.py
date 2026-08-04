from django.db import transaction

from apps.medicines.models import InventoryBatch, MedicineItem
from apps.ocr.models import OCRJob


@transaction.atomic
def confirm_job(*, job_id, user, fields):
    job = OCRJob.objects.select_for_update().get(id=job_id, user=user)
    # 重复确认返回首次创建的批次，避免网络重试造成库存重复。
    if job.confirmed_batch_id:
        return job.confirmed_batch, False
    if job.status != OCRJob.Status.SUCCEEDED:
        raise ValueError("ocr_job_not_ready")

    medicine, _ = MedicineItem.objects.get_or_create(
        owner=user,
        name=fields["medicine_name"].strip(),
        specification=fields.get("specification", "").strip(),
    )
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        batch_number=fields.get("batch_number", "").strip(),
        production_date=fields.get("production_date"),
        expiry_date=fields.get("expiry_date"),
        quantity=fields.get("quantity", 1),
    )
    job.confirmed_batch = batch
    job.status = OCRJob.Status.CONFIRMED
    job.save(
        update_fields=["confirmed_batch", "status", "updated_at"]
    )
    return batch, True

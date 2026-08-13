from django.db import transaction

from apps.medicines.models import InventoryBatch, MedicineItem
from apps.medicines.services.photos import medicine_photo_key
from apps.medicines.services.access import resolve_inventory_scope
from apps.ocr.providers.storage import get_object_storage
from apps.ocr.models import OCRJob
from apps.families.services import record_event


@transaction.atomic
def confirm_job(*, job_id, user, fields):
    job = OCRJob.objects.select_for_update().get(id=job_id, user=user)
    # 重复确认返回首次创建的批次，避免网络重试造成库存重复。
    if job.confirmed_batch_id:
        return job.confirmed_batch, False
    if job.status != OCRJob.Status.SUCCEEDED:
        raise ValueError("ocr_job_not_ready")

    manufacturer = fields.get("manufacturer", "").strip()
    ownership = resolve_inventory_scope(user, fields.get("scope", "personal"))
    medicine, created = MedicineItem.objects.get_or_create(
        **ownership,
        name=fields["medicine_name"].strip(),
        specification=fields.get("specification", "").strip(),
        defaults={"manufacturer": manufacturer},
    )
    changed_fields = []
    if not created and manufacturer and not medicine.manufacturer:
        medicine.manufacturer = manufacturer
        changed_fields.append("manufacturer")

    front_key = job.image_keys.get("front")
    expected_prefix = f"ocr/tmp/{user.id}/"
    if (
        fields.get("retain_front_photo", True)
        and front_key
        and front_key.startswith(expected_prefix)
        and not medicine.photo_object_key
    ):
        content_type = "image/png" if front_key.endswith(".png") else "image/jpeg"
        destination_key = medicine_photo_key(
            user_id=user.id,
            content_type=content_type,
        )
        storage = get_object_storage()
        storage.copy(source_key=front_key, destination_key=destination_key)
        medicine.photo_object_key = destination_key
        medicine.photo_content_type = content_type
        changed_fields.extend(["photo_object_key", "photo_content_type"])
    if changed_fields:
        medicine.save(update_fields=changed_fields)
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        batch_number=fields.get("batch_number", "").strip(),
        production_date=fields.get("production_date"),
        expiry_date=fields.get("expiry_date"),
        quantity=fields.get("quantity", 1),
        created_by=user,
        updated_by=user,
    )
    job.confirmed_batch = batch
    job.status = OCRJob.Status.CONFIRMED
    job.save(
        update_fields=["confirmed_batch", "status", "updated_at"]
    )
    if medicine.family_id:
        record_event(
            family=medicine.family,
            actor=user,
            event_type="inventory_created",
            payload={"batch_id": str(batch.id), "source": "ocr"},
        )
    return batch, True

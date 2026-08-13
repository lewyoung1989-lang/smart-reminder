from dataclasses import dataclass
from datetime import datetime, timedelta
import logging
import uuid

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.ocr.providers.storage import get_object_storage


logger = logging.getLogger(__name__)


SUPPORTED_PHOTO_TYPES = {"image/jpeg": ".jpg", "image/png": ".png"}


@dataclass(frozen=True)
class MedicinePhotoUploadGrant:
    object_key: str
    upload_url: str
    headers: dict[str, str]
    expires_at: datetime


def medicine_photo_key(*, user_id, content_type: str) -> str:
    try:
        suffix = SUPPORTED_PHOTO_TYPES[content_type]
    except KeyError as error:
        raise ValueError("unsupported_image_type") from error
    return f"medicine-photos/{user_id}/{uuid.uuid4()}{suffix}"


def create_medicine_photo_upload(
    *, user, content_type: str, byte_length: int, storage
) -> MedicinePhotoUploadGrant:
    if content_type not in SUPPORTED_PHOTO_TYPES:
        raise ValueError("unsupported_image_type")
    if byte_length <= 0:
        raise ValueError("invalid_image_size")
    if byte_length > settings.OCR_MAX_IMAGE_BYTES:
        raise ValueError("image_too_large")
    key = medicine_photo_key(user_id=user.id, content_type=content_type)
    signed = storage.presign_put(
        key=key,
        content_type=content_type,
        expires_in=settings.OCR_UPLOAD_URL_TTL_SECONDS,
    )
    return MedicinePhotoUploadGrant(
        object_key=key,
        upload_url=signed["url"],
        headers=signed["headers"],
        expires_at=timezone.now()
        + timedelta(seconds=settings.OCR_UPLOAD_URL_TTL_SECONDS),
    )


def validate_medicine_photo_key(*, user, object_key: str) -> None:
    prefix = f"medicine-photos/{user.id}/"
    if not object_key.startswith(prefix) or not object_key.endswith((".jpg", ".png")):
        raise ValueError("invalid_photo_object_key")


def photo_content_type(object_key: str) -> str:
    return "image/png" if object_key.endswith(".png") else "image/jpeg"


def delete_replaced_photo_after_commit(object_key: str) -> None:
    if not object_key:
        return

    def delete_photo():
        try:
            get_object_storage().delete(object_key)
        except Exception:
            # 新照片已经入库，旧照片清理失败不应让用户保存失败。
            logger.warning("medicine_photo_delete_failed")

    transaction.on_commit(delete_photo)

from dataclasses import dataclass
from datetime import datetime, timedelta
import uuid

from django.conf import settings
from django.utils import timezone


@dataclass(frozen=True)
class UploadGrant:
    object_key: str
    upload_url: str
    headers: dict[str, str]
    expires_at: datetime


def create_upload(
    *,
    user,
    kind: str,
    content_type: str,
    byte_length: int,
    storage,
) -> UploadGrant:
    if kind not in {"front", "expiry"}:
        raise ValueError("invalid_image_kind")
    if content_type not in {"image/jpeg", "image/png"}:
        raise ValueError("unsupported_image_type")
    if byte_length <= 0:
        raise ValueError("invalid_image_size")
    if byte_length > settings.OCR_MAX_IMAGE_BYTES:
        raise ValueError("image_too_large")

    # 对象键按用户隔离且不包含药名等敏感信息。
    suffix = ".jpg" if content_type == "image/jpeg" else ".png"
    key = f"ocr/tmp/{user.id}/{uuid.uuid4()}{suffix}"
    signed = storage.presign_put(
        key=key,
        content_type=content_type,
        expires_in=settings.OCR_UPLOAD_URL_TTL_SECONDS,
    )
    return UploadGrant(
        object_key=key,
        upload_url=signed["url"],
        headers=signed["headers"],
        expires_at=timezone.now()
        + timedelta(seconds=settings.OCR_UPLOAD_URL_TTL_SECONDS),
    )

import pytest

from apps.medicines.services.photos import create_medicine_photo_upload


class FakeStorage:
    def presign_put(self, *, key, content_type, expires_in):
        return {
            "url": f"https://upload.invalid/{key}",
            "headers": {"Content-Type": content_type},
        }


def test_creates_user_scoped_medicine_photo_upload(user, settings):
    settings.OCR_MAX_IMAGE_BYTES = 1024
    settings.OCR_UPLOAD_URL_TTL_SECONDS = 600

    grant = create_medicine_photo_upload(
        user=user,
        content_type="image/jpeg",
        byte_length=512,
        storage=FakeStorage(),
    )

    assert grant.object_key.startswith(f"medicine-photos/{user.id}/")
    assert grant.object_key.endswith(".jpg")
    assert grant.headers == {"Content-Type": "image/jpeg"}


def test_rejects_oversized_medicine_photo(user, settings):
    settings.OCR_MAX_IMAGE_BYTES = 10

    with pytest.raises(ValueError, match="image_too_large"):
        create_medicine_photo_upload(
            user=user,
            content_type="image/jpeg",
            byte_length=11,
            storage=FakeStorage(),
        )

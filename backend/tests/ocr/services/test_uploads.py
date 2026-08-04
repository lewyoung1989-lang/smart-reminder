import pytest

from apps.ocr.services.uploads import create_upload


class FakeStorage:
    def presign_put(self, *, key, content_type, expires_in):
        return {
            "url": f"https://upload.invalid/{key}",
            "headers": {"Content-Type": content_type},
        }


def test_upload_key_is_random_and_scoped_to_user(user):
    result = create_upload(
        user=user,
        kind="front",
        content_type="image/jpeg",
        byte_length=100_000,
        storage=FakeStorage(),
    )
    assert result.object_key.startswith(f"ocr/tmp/{user.id}/")
    assert result.object_key.endswith(".jpg")
    assert result.upload_url.startswith("https://upload.invalid/")


def test_rejects_oversized_image(settings, user):
    settings.OCR_MAX_IMAGE_BYTES = 10
    with pytest.raises(ValueError, match="image_too_large"):
        create_upload(
            user=user,
            kind="front",
            content_type="image/jpeg",
            byte_length=11,
            storage=FakeStorage(),
        )

import cv2
import numpy as np
import pytest

from apps.ocr.services.image_validation import (
    ImageValidationError,
    prepare_ocr_variants,
)


def _jpeg():
    image = np.full((80, 160, 3), 150, dtype=np.uint8)
    cv2.putText(
        image,
        "202801",
        (10, 50),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (130, 130, 130),
        2,
    )
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    return encoded.tobytes()


def test_front_uses_only_normalized_image():
    variants = prepare_ocr_variants(_jpeg(), role="front")

    assert len(variants) == 1
    assert (
        cv2.imdecode(
            np.frombuffer(variants[0], np.uint8),
            cv2.IMREAD_COLOR,
        )
        is not None
    )


def test_expiry_adds_contrast_enhanced_variant():
    variants = prepare_ocr_variants(_jpeg(), role="expiry")

    assert len(variants) == 2
    assert variants[0] != variants[1]


def test_expiry_keeps_original_when_enhancement_fails(monkeypatch):
    def fail_enhancement(image):
        raise cv2.error("enhancement_failed")

    monkeypatch.setattr(
        "apps.ocr.services.image_validation._enhance_expiry",
        fail_enhancement,
    )

    variants = prepare_ocr_variants(_jpeg(), role="expiry")

    assert len(variants) == 1


def test_invalid_image_keeps_fixed_error_code():
    with pytest.raises(ImageValidationError, match="image_decode_failed"):
        prepare_ocr_variants(b"not-an-image", role="expiry")

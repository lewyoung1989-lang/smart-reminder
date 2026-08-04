import cv2
import numpy as np
from django.conf import settings


class ImageValidationError(ValueError):
    pass


def validate_and_resize(value: bytes) -> bytes:
    if not value:
        raise ImageValidationError("invalid_image")
    if len(value) > settings.OCR_MAX_IMAGE_BYTES:
        raise ImageValidationError("image_too_large")

    # 错误只返回固定代码，不能把药盒图片字节或识别内容带入日志。
    image = cv2.imdecode(
        np.frombuffer(value, dtype=np.uint8),
        cv2.IMREAD_COLOR,
    )
    if image is None:
        raise ImageValidationError("image_decode_failed")

    height, width = image.shape[:2]
    longest = max(height, width)
    if longest > settings.OCR_MAX_IMAGE_SIDE:
        scale = settings.OCR_MAX_IMAGE_SIDE / longest
        image = cv2.resize(
            image,
            (round(width * scale), round(height * scale)),
            interpolation=cv2.INTER_AREA,
        )

    ok, encoded = cv2.imencode(
        ".jpg",
        image,
        [cv2.IMWRITE_JPEG_QUALITY, 90],
    )
    if not ok:
        raise ImageValidationError("image_encode_failed")
    return encoded.tobytes()

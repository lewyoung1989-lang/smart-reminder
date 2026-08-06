from typing import Protocol

from apps.ocr.domain.types import ImageRole, OCRDocument


class OCRProvider(Protocol):
    def recognize(
        self,
        image_bytes: bytes,
        *,
        role: ImageRole,
    ) -> OCRDocument: ...

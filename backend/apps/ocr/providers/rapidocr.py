from functools import lru_cache
from pathlib import Path

from django.conf import settings
from rapidocr import RapidOCR

from apps.ocr.domain.types import ImageRole, OCRDocument, OCRLine


@lru_cache(maxsize=1)
def get_engine():
    params = {"Rec.lang_type": settings.OCR_LANGUAGE}
    if settings.OCR_MODEL_ROOT:
        root = Path(settings.OCR_MODEL_ROOT)
        params.update(
            {
                "Det.model_path": str(root / "det.onnx"),
                "Cls.model_path": str(root / "cls.onnx"),
                "Rec.model_path": str(root / "rec.onnx"),
            }
        )
    return RapidOCR(params=params)


class RapidOCRProvider:
    def __init__(self, *, engine=None, minimum_score=None):
        self._engine = engine
        self._minimum_score = (
            settings.OCR_TEXT_SCORE
            if minimum_score is None
            else minimum_score
        )

    def recognize(
        self,
        image_bytes: bytes,
        *,
        role: ImageRole,
    ) -> OCRDocument:
        result = (self._engine or get_engine())(image_bytes)
        lines = []
        if result is not None and result.txts is not None:
            for box, value, score in zip(
                result.boxes,
                result.txts,
                result.scores,
                strict=True,
            ):
                if float(score) < self._minimum_score:
                    continue
                points = tuple(
                    tuple(float(coordinate) for coordinate in point)
                    for point in box
                )
                lines.append(
                    OCRLine(
                        box=points,
                        text=value.strip(),
                        score=float(score),
                    )
                )
        return OCRDocument(role=role, lines=tuple(lines))

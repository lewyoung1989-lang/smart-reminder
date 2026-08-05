import logging
import re

from apps.ocr.domain.types import OCRDocument


logger = logging.getLogger(__name__)
CONTROL_CHARACTERS = re.compile(r"[\x00-\x1f\x7f]+")
MAX_LOGGED_TEXT_LENGTH = 200


def _safe_text(value: str) -> str:
    sanitized = CONTROL_CHARACTERS.sub(" ", value).replace('"', "'")
    return sanitized.strip()[:MAX_LOGGED_TEXT_LENGTH]


def log_ocr_documents(
    job_id,
    documents: tuple[OCRDocument, ...],
    *,
    enabled: bool,
) -> None:
    if not enabled:
        return
    for document in documents:
        for index, line in enumerate(document.lines):
            logger.info(
                'ocr_text job_id=%s role=%s line=%d score=%.4f text="%s"',
                job_id,
                document.role,
                index,
                line.score,
                _safe_text(line.text),
            )

import logging

from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.services.debug_logging import log_ocr_documents


def _document(text):
    return OCRDocument(
        role="expiry",
        lines=(
            OCRLine(
                ((0, 0), (20, 0), (20, 10), (0, 10)),
                text,
                0.98214,
            ),
        ),
    )


def test_debug_logging_is_silent_when_disabled(caplog):
    with caplog.at_level(logging.INFO):
        log_ocr_documents(
            "job-1",
            (_document("有效期至2028.05"),),
            enabled=False,
        )

    assert "有效期至2028.05" not in caplog.text


def test_debug_logging_sanitizes_and_truncates_text(caplog):
    value = '有效"期\n至\t' + "2" * 250

    with caplog.at_level(logging.INFO):
        log_ocr_documents("job-1", (_document(value),), enabled=True)

    assert "job_id=job-1 role=expiry line=0 score=0.9821" in caplog.text
    assert "\n至" not in caplog.text
    logged_value = caplog.text.split('text="', 1)[1].split('"', 1)[0]
    assert len(logged_value) == 200
    assert '"' not in logged_value

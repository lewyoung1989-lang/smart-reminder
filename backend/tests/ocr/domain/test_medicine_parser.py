from datetime import date

import pytest

from apps.ocr.domain.medicine_parser import extract_candidates
from apps.ocr.domain.types import OCRDocument, OCRLine


def line(text, score=0.95):
    return OCRLine(
        box=((0, 0), (1, 0), (1, 1), (0, 1)),
        text=text,
        score=score,
    )


def test_extracts_front_and_expiry_fields():
    result = extract_candidates(
        (
            OCRDocument(
                "front",
                (line("布洛芬缓释胶囊"), line("规格 0.3g*20粒")),
            ),
            OCRDocument(
                "expiry",
                (line("批号 20260108"), line("有效期至 2028.05")),
            ),
        )
    )
    assert result.medicine_name == "布洛芬缓释胶囊"
    assert result.specification == "0.3g*20粒"
    assert result.batch_number == "20260108"
    assert result.expiry_date == date(2028, 5, 31)


def test_keeps_production_date_separate_from_expiry_date():
    result = extract_candidates(
        (
            OCRDocument(
                "expiry",
                (
                    line("生产日期 2026/01/08"),
                    line("EXP 05/28"),
                ),
            ),
        )
    )
    assert result.production_date == date(2026, 1, 8)
    assert result.expiry_date == date(2028, 5, 31)


def test_unlabelled_date_is_not_promoted_to_expiry():
    result = extract_candidates(
        (OCRDocument("expiry", (line("2026.01.08"),)),)
    )
    assert result.production_date is None
    assert result.expiry_date is None


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("有效期 2028/05/31", date(2028, 5, 31)),
        ("失效期2028年5月", date(2028, 5, 31)),
        ("EXP 2028.05", date(2028, 5, 31)),
        ("EXP 05/28", date(2028, 5, 31)),
    ],
)
def test_supported_expiry_formats(text, expected):
    result = extract_candidates(
        (OCRDocument("expiry", (line(text),)),)
    )
    assert result.expiry_date == expected

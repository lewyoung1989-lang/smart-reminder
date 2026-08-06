from datetime import date

import pytest

from apps.ocr.domain.medicine_parser import extract_candidates
from apps.ocr.domain.types import OCRDocument, OCRLine


def line(text, score=0.95, *, x=0, y=0, width=100, height=10):
    return OCRLine(
        box=(
            (x, y),
            (x + width, y),
            (x + width, y + height),
            (x, y + height),
        ),
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


def test_rejects_composition_sentence_as_medicine_name():
    result = extract_candidates(
        (
            OCRDocument(
                "front",
                (
                    line("每片中阿莫西林含量0.25g", 0.99, width=220),
                    line("阿莫西林胶囊", 0.94, y=20, width=120),
                ),
            ),
        )
    )

    assert result.medicine_name == "阿莫西林胶囊"


def test_rejects_bare_dosage_form_as_medicine_name():
    result = extract_candidates(
        (OCRDocument("front", (line("鼻喷雾剂"),)),)
    )

    assert result.medicine_name == ""


def test_supports_common_injection_medicine_name():
    result = extract_candidates(
        (OCRDocument("front", (line("盐酸氨溴索注射液"),)),)
    )

    assert result.medicine_name == "盐酸氨溴索注射液"


def test_rejects_bare_injection_dosage_form():
    result = extract_candidates(
        (OCRDocument("front", (line("注射液"),)),)
    )

    assert result.medicine_name == ""


def test_specific_name_beats_larger_short_name():
    result = extract_candidates(
        (
            OCRDocument(
                "front",
                (
                    line("布洛芬片", 0.99, width=400, height=40),
                    line("布洛芬缓释胶囊", 0.94, y=50, width=150),
                ),
            ),
        )
    )

    assert result.medicine_name == "布洛芬缓释胶囊"


def test_parses_dates_split_across_adjacent_lines():
    result = extract_candidates(
        (
            OCRDocument(
                "expiry",
                (
                    line("生产日期", y=10, width=60),
                    line("20260108", y=25, width=80),
                    line("有效期至", y=50, width=60),
                    line("202805", y=65, width=80),
                ),
            ),
        )
    )

    assert result.production_date == date(2026, 1, 8)
    assert result.expiry_date == date(2028, 5, 31)


def test_compact_unlabelled_number_is_not_promoted():
    result = extract_candidates(
        (OCRDocument("expiry", (line("20260108"),)),)
    )

    assert result.production_date is None
    assert result.expiry_date is None


def test_conflicting_dates_are_left_for_user_confirmation():
    result = extract_candidates(
        (
            OCRDocument(
                "expiry",
                (
                    line("生产日期20290108", y=10),
                    line("有效期至202805", y=30),
                ),
            ),
        )
    )

    assert result.production_date is None
    assert result.expiry_date is None


def test_expired_date_is_preserved_for_expiry_management():
    result = extract_candidates(
        (OCRDocument("expiry", (line("有效期至202405"),)),),
        reference_date=date(2026, 8, 5),
    )

    assert result.expiry_date == date(2024, 5, 31)


def test_future_production_date_is_left_for_user_confirmation():
    result = extract_candidates(
        (OCRDocument("expiry", (line("生产日期20290108"),)),),
        reference_date=date(2026, 8, 5),
    )

    assert result.production_date is None

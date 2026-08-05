from apps.ocr.domain.layout import build_text_windows, merge_documents
from apps.ocr.domain.types import OCRDocument, OCRLine


def _line(text, x, y, *, width=100, height=10, score=0.90):
    return OCRLine(
        (
            (x, y),
            (x + width, y),
            (x + width, y + height),
            (x, y + height),
        ),
        text,
        score,
    )


def test_merge_keeps_best_nearby_duplicate_and_layout_order():
    merged = merge_documents(
        "expiry",
        (
            OCRDocument(
                "expiry",
                (_line("20280108", 0, 30, score=0.80),),
            ),
            OCRDocument(
                "expiry",
                (
                    _line("20280108", 2, 31, score=0.97),
                    _line("生产日期", 0, 10, score=0.95),
                ),
            ),
        ),
    )

    assert [line.text for line in merged.lines] == ["生产日期", "20280108"]
    assert merged.lines[1].score == 0.97


def test_merge_preserves_same_text_in_different_regions():
    merged = merge_documents(
        "front",
        (
            OCRDocument(
                "front",
                (
                    _line("布洛芬缓释胶囊", 0, 10),
                    _line("布洛芬缓释胶囊", 0, 110),
                ),
            ),
        ),
    )

    assert len(merged.lines) == 2


def test_merge_drops_empty_text_lines():
    merged = merge_documents(
        "expiry",
        (OCRDocument("expiry", (_line(" ", 0, 10),)),),
    )

    assert merged.lines == ()


def test_adjacent_label_and_value_create_vertical_window():
    document = OCRDocument(
        "expiry",
        (
            _line("生产日期", 10, 10, width=60),
            _line("20280108", 12, 25, width=80),
        ),
    )

    windows = build_text_windows(document)

    assert any(window.text == "生产日期20280108" for window in windows)
    assert any(window.line_indices == (0, 1) for window in windows)


def test_nearby_same_row_label_and_value_create_horizontal_window():
    document = OCRDocument(
        "expiry",
        (
            _line("有效期至", 0, 10, width=50),
            _line("2028.05", 60, 10, width=70),
        ),
    )

    assert any(
        window.text == "有效期至2028.05"
        for window in build_text_windows(document)
    )


def test_layout_finds_same_column_value_past_an_unrelated_column():
    document = OCRDocument(
        "expiry",
        (
            _line("生产日期", 0, 10, width=60),
            _line("厂家", 250, 12, width=40),
            _line("20280108", 2, 28, width=80),
        ),
    )

    windows = build_text_windows(document)

    assert any(window.text == "生产日期20280108" for window in windows)
    assert all(window.text != "生产日期厂家" for window in windows)


def test_vertical_value_survives_a_nearby_horizontal_label():
    document = OCRDocument(
        "expiry",
        (
            _line("生产日期", 0, 10, width=50),
            _line("有效期至", 60, 10, width=50),
            _line("20280108", 0, 30, width=80),
        ),
    )

    windows = build_text_windows(document)

    assert any(window.text == "生产日期20280108" for window in windows)


def test_distant_lines_and_columns_are_not_joined():
    document = OCRDocument(
        "expiry",
        (
            _line("生产日期", 0, 10, width=60),
            _line("20280108", 300, 10, width=80),
            _line("20290108", 0, 100, width=80),
        ),
    )

    assert all(
        len(window.line_indices) == 1
        for window in build_text_windows(document)
    )

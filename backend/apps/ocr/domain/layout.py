import re
from dataclasses import dataclass

from .types import OCRDocument, OCRLine


@dataclass(frozen=True)
class OCRTextWindow:
    text: str
    score: float
    line_indices: tuple[int, ...]


def _normalized(value: str) -> str:
    return re.sub(r"\s+", "", value).casefold()


def _top(line: OCRLine) -> float:
    return min(point[1] for point in line.box)


def _bottom(line: OCRLine) -> float:
    return max(point[1] for point in line.box)


def _left(line: OCRLine) -> float:
    return min(point[0] for point in line.box)


def _right(line: OCRLine) -> float:
    return max(point[0] for point in line.box)


def _width(line: OCRLine) -> float:
    return max(1.0, _right(line) - _left(line))


def _height(line: OCRLine) -> float:
    return max(1.0, _bottom(line) - _top(line))


def _center(line: OCRLine) -> tuple[float, float]:
    return (
        (_left(line) + _right(line)) / 2,
        (_top(line) + _bottom(line)) / 2,
    )


def _same_region(left: OCRLine, right: OCRLine) -> bool:
    left_center = _center(left)
    right_center = _center(right)
    return (
        abs(left_center[0] - right_center[0])
        <= max(4.0, max(_width(left), _width(right)) * 0.2)
        and abs(left_center[1] - right_center[1])
        <= max(4.0, max(_height(left), _height(right)) * 0.75)
    )


def merge_documents(
    role: str,
    documents: tuple[OCRDocument, ...],
) -> OCRDocument:
    selected: list[tuple[str, OCRLine]] = []
    for document in documents:
        for line in document.lines:
            key = _normalized(line.text)
            if not key:
                continue
            duplicate_index = next(
                (
                    index
                    for index, (existing_key, existing) in enumerate(selected)
                    if existing_key == key and _same_region(existing, line)
                ),
                None,
            )
            if duplicate_index is None:
                selected.append((key, line))
            elif line.score > selected[duplicate_index][1].score:
                selected[duplicate_index] = (key, line)
    ordered = sorted(
        (line for key, line in selected),
        key=lambda line: (_top(line), _left(line)),
    )
    return OCRDocument(role=role, lines=tuple(ordered))


def _adjacency_distance(current: OCRLine, following: OCRLine) -> float | None:
    height = max(_height(current), _height(following))
    vertical_overlap = min(_bottom(current), _bottom(following)) - max(
        _top(current),
        _top(following),
    )
    horizontal_gap = _left(following) - _right(current)
    if (
        vertical_overlap >= min(_height(current), _height(following)) * 0.5
        and 0 <= horizontal_gap <= height * 3
    ):
        return horizontal_gap / height

    vertical_gap = _top(following) - _bottom(current)
    horizontal_overlap = min(_right(current), _right(following)) - max(
        _left(current),
        _left(following),
    )
    left_delta = abs(_left(current) - _left(following))
    if (
        -height * 0.25 <= vertical_gap <= height * 2.5
        and (horizontal_overlap > 0 or left_delta <= height * 2)
    ):
        return 1 + max(0.0, vertical_gap) / height + left_delta / max(
            _width(current),
            _width(following),
        )
    return None


def build_text_windows(document: OCRDocument) -> tuple[OCRTextWindow, ...]:
    windows = [
        OCRTextWindow(line.text, line.score, (index,))
        for index, line in enumerate(document.lines)
    ]
    for index, line in enumerate(document.lines):
        candidates = []
        for following_index in range(index + 1, len(document.lines)):
            following = document.lines[following_index]
            distance = _adjacency_distance(line, following)
            if distance is not None:
                candidates.append((distance, following_index, following))
        if not candidates:
            continue
        _, following_index, following = min(candidates, key=lambda value: value[0])
        windows.append(
            OCRTextWindow(
                f"{line.text}{following.text}",
                min(line.score, following.score),
                (index, following_index),
            )
        )
    return tuple(windows)

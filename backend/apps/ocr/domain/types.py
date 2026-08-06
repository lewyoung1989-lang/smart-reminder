from dataclasses import dataclass
from datetime import date
from typing import Literal


Point = tuple[float, float]
ImageRole = Literal["front", "expiry"]


@dataclass(frozen=True)
class OCRLine:
    box: tuple[Point, Point, Point, Point]
    text: str
    score: float


@dataclass(frozen=True)
class OCRDocument:
    role: ImageRole
    lines: tuple[OCRLine, ...]


@dataclass(frozen=True)
class MedicineCandidates:
    medicine_name: str = ""
    specification: str = ""
    batch_number: str = ""
    production_date: date | None = None
    expiry_date: date | None = None
    confidence: dict[str, float] | None = None

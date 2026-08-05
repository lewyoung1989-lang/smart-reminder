from datetime import date

from apps.ocr.domain.semantic import EvidenceField, MedicineSemanticData
from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.providers.deepseek import DeepSeekMedicineError
from apps.ocr.services.candidate_resolver import resolve_candidates


def _line(text, score=0.95, *, y=0):
    return OCRLine(
        ((0, y), (120, y), (120, y + 10), (0, y + 10)),
        text,
        score,
    )


def _semantic(**overrides):
    values = {
        "medicine_name": None,
        "specification": None,
        "batch_number": None,
        "production_date_text": None,
        "expiry_date_text": None,
        "ambiguities": [],
    }
    values.update(overrides)
    return MedicineSemanticData(**values)


class StaticSemanticProvider:
    def __init__(self, result):
        self.result = result

    def parse(self, documents):
        return self.result


class FailingSemanticProvider:
    def parse(self, documents):
        raise DeepSeekMedicineError("medicine_semantic_request_failed")


def test_semantic_name_overrides_local_name_with_evidence_confidence():
    documents = (
        OCRDocument(
            "front",
            (
                _line("阿莫西林克拉维酸钾胶囊", 0.97),
                _line("阿莫西林胶囊", 0.88, y=20),
            ),
        ),
    )
    semantic = _semantic(
        medicine_name=EvidenceField(
            value="阿莫西林胶囊",
            line_ids=["front:1"],
        )
    )

    result = resolve_candidates(
        documents,
        semantic_provider=StaticSemanticProvider(semantic),
    )

    assert result.medicine_name == "阿莫西林胶囊"
    assert result.confidence["medicine_name"] == 0.88


def test_semantic_date_fills_an_unlabelled_local_value():
    documents = (OCRDocument("expiry", (_line("202805", 0.91),)),)
    semantic = _semantic(
        expiry_date_text=EvidenceField(
            value="202805",
            line_ids=["expiry:0"],
        )
    )

    result = resolve_candidates(
        documents,
        semantic_provider=StaticSemanticProvider(semantic),
    )

    assert result.expiry_date == date(2028, 5, 31)
    assert result.confidence["expiry_date"] == 0.91


def test_local_high_precision_date_beats_semantic_date():
    documents = (
        OCRDocument(
            "expiry",
            (
                _line("有效期至2029.05", 0.96),
                _line("202805", 0.91, y=30),
            ),
        ),
    )
    semantic = _semantic(
        expiry_date_text=EvidenceField(
            value="202805",
            line_ids=["expiry:1"],
        )
    )

    result = resolve_candidates(
        documents,
        semantic_provider=StaticSemanticProvider(semantic),
    )

    assert result.expiry_date == date(2029, 5, 31)
    assert result.confidence["expiry_date"] == 0.96


def test_semantic_failure_returns_local_candidates():
    documents = (OCRDocument("front", (_line("阿莫西林胶囊"),)),)

    result = resolve_candidates(
        documents,
        semantic_provider=FailingSemanticProvider(),
    )

    assert result.medicine_name == "阿莫西林胶囊"


def test_semantic_production_date_conflicting_with_expiry_clears_both():
    documents = (
        OCRDocument(
            "expiry",
            (
                _line("有效期至2028.05", 0.96),
                _line("20290108", 0.91, y=30),
            ),
        ),
    )
    semantic = _semantic(
        production_date_text=EvidenceField(
            value="20290108",
            line_ids=["expiry:1"],
        )
    )

    result = resolve_candidates(
        documents,
        semantic_provider=StaticSemanticProvider(semantic),
    )

    assert result.production_date is None
    assert result.expiry_date is None
    assert "production_date" not in result.confidence
    assert "expiry_date" not in result.confidence

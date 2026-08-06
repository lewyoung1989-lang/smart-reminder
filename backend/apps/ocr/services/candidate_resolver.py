import logging
from datetime import date

from apps.ocr.domain.medicine_parser import extract_candidates, parse_date_value
from apps.ocr.domain.semantic import EvidenceField
from apps.ocr.domain.types import MedicineCandidates, OCRDocument
from apps.ocr.providers.deepseek import DeepSeekMedicineError


logger = logging.getLogger(__name__)


def _evidence_score(
    documents: tuple[OCRDocument, ...],
    field: EvidenceField,
) -> float | None:
    scores = {
        f"{document.role}:{index}": line.score
        for document in documents
        for index, line in enumerate(document.lines)
    }
    selected = [scores.get(line_id) for line_id in field.line_ids]
    if any(score is None for score in selected):
        return None
    return min(selected)


def _set_semantic_confidence(
    confidence: dict[str, float],
    name: str,
    documents: tuple[OCRDocument, ...],
    field: EvidenceField,
) -> None:
    score = _evidence_score(documents, field)
    if score is None:
        confidence.pop(name, None)
    else:
        confidence[name] = score


def resolve_candidates(
    documents: tuple[OCRDocument, ...],
    *,
    semantic_provider=None,
    reference_date: date | None = None,
) -> MedicineCandidates:
    local = extract_candidates(documents, reference_date=reference_date)
    if semantic_provider is None:
        return local
    try:
        semantic = semantic_provider.parse(documents)
    except DeepSeekMedicineError:
        logger.info("ocr_semantic_fallback error_code=semantic_unavailable")
        return local

    confidence = dict(local.confidence or {})
    medicine_name = local.medicine_name
    if semantic.medicine_name is not None:
        medicine_name = semantic.medicine_name.value
        _set_semantic_confidence(
            confidence,
            "medicine_name",
            documents,
            semantic.medicine_name,
        )

    specification = local.specification
    if not specification and semantic.specification is not None:
        specification = semantic.specification.value
        _set_semantic_confidence(
            confidence,
            "specification",
            documents,
            semantic.specification,
        )

    batch_number = local.batch_number
    if not batch_number and semantic.batch_number is not None:
        batch_number = semantic.batch_number.value
        _set_semantic_confidence(
            confidence,
            "batch_number",
            documents,
            semantic.batch_number,
        )

    production_date = local.production_date
    if production_date is None and semantic.production_date_text is not None:
        production_date = parse_date_value(
            semantic.production_date_text.value,
            allow_month_year=False,
        )
        if production_date is not None:
            _set_semantic_confidence(
                confidence,
                "production_date",
                documents,
                semantic.production_date_text,
            )

    expiry_date = local.expiry_date
    if expiry_date is None and semantic.expiry_date_text is not None:
        expiry_date = parse_date_value(
            semantic.expiry_date_text.value,
            allow_month_year=True,
        )
        if expiry_date is not None:
            _set_semantic_confidence(
                confidence,
                "expiry_date",
                documents,
                semantic.expiry_date_text,
            )

    if production_date and expiry_date and production_date > expiry_date:
        production_date = None
        expiry_date = None
        confidence.pop("production_date", None)
        confidence.pop("expiry_date", None)
    if reference_date and production_date and production_date > reference_date:
        production_date = None
        confidence.pop("production_date", None)

    return MedicineCandidates(
        medicine_name=medicine_name,
        specification=specification,
        batch_number=batch_number,
        production_date=production_date,
        expiry_date=expiry_date,
        confidence=confidence,
    )

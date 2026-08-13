import calendar
import re
from datetime import date

from .layout import build_text_windows
from .types import MedicineCandidates, OCRDocument


EXPIRY_LABEL = re.compile(r"有效期(?:至)?|失效期|EXP", re.IGNORECASE)
PRODUCTION_LABEL = re.compile(r"生产日期|生产日|MFG", re.IGNORECASE)
MANUFACTURER = re.compile(
    r"(?:生产企业|生产厂家|生产厂商|制造商|厂家)\s*[:：]?\s*"
    r"([^，。；;]{2,80}(?:公司|药业|制药厂|制药|集团|有限责任公司))"
)
BATCH = re.compile(
    r"(?:批号|产品批号|LOT)\s*[:：]?\s*([A-Z0-9-]{4,30})",
    re.IGNORECASE,
)
SPEC = re.compile(
    r"(?:规格\s*[:：]?\s*)?"
    r"((?:\d+(?:\.\d+)?)(?:mg|g|ml|毫克|克|毫升)"
    r"(?:[*/xX×]\d+(?:片|粒|袋|支|瓶))?)",
    re.IGNORECASE,
)
DATE_YMD = re.compile(
    r"(20\d{2})[年./-](\d{1,2})(?:[月./-](\d{1,2})日?)?"
)
DATE_MY = re.compile(r"(?<!\d)(\d{1,2})[./-](\d{2})(?!\d)")
DATE_COMPACT = re.compile(
    r"(?<!\d)(20\d{2})(0[1-9]|1[0-2])([0-3]\d)?(?!\d)"
)
NAME_EXCLUSION = re.compile(
    r"每(?:片|粒|袋|支)中|含量|成份|成分|用法|批准文号|"
    r"请仔细阅读|适应症"
)
BARE_DOSAGE_FORM = re.compile(
    r"^(?:片剂|胶囊剂?|颗粒剂?|口服液|滴丸|丸剂?|喷雾剂|"
    r"鼻喷雾剂|气雾剂|"
    r"吸入剂|注射液|滴眼液|滴耳液|混悬液|溶液剂?|软膏剂?|"
    r"眼膏|乳膏剂?|凝胶剂?|洗剂|酊剂|散剂?|栓剂?|贴剂?|糖浆剂?)$"
)
DOSAGE_FORM_SUFFIX = re.compile(
    r"(?:片剂?|胶囊剂?|颗粒剂?|口服液|滴丸|丸剂?|喷雾剂|气雾剂|"
    r"吸入剂|注射液|滴眼液|滴耳液|混悬液|溶液剂?|软膏剂?|"
    r"眼膏|乳膏剂?|凝胶剂?|洗剂|酊剂|散剂?|栓剂?|贴剂?|糖浆剂?)$"
)


def _month_end(year: int, month: int) -> date | None:
    try:
        return date(year, month, calendar.monthrange(year, month)[1])
    except ValueError:
        return None


def parse_date_value(text: str, *, allow_month_year: bool) -> date | None:
    ymd = DATE_YMD.search(text)
    if ymd:
        year = int(ymd.group(1))
        month = int(ymd.group(2))
        if ymd.group(3):
            try:
                return date(year, month, int(ymd.group(3)))
            except ValueError:
                return None
        return _month_end(year, month) if allow_month_year else None

    compact = DATE_COMPACT.search(re.sub(r"\s+", "", text))
    if compact:
        year = int(compact.group(1))
        month = int(compact.group(2))
        if compact.group(3):
            try:
                return date(year, month, int(compact.group(3)))
            except ValueError:
                return None
        return _month_end(year, month) if allow_month_year else None

    if allow_month_year:
        month_year = DATE_MY.search(text)
        if month_year:
            month = int(month_year.group(1))
            year = 2000 + int(month_year.group(2))
            return _month_end(year, month)
    return None


def _labelled_date(
    text: str,
    label: re.Pattern,
    *,
    allow_month_year: bool,
) -> date | None:
    match = label.search(text)
    if not match:
        return None
    return parse_date_value(
        text[match.end() :],
        allow_month_year=allow_month_year,
    )


def _medicine_name(document: OCRDocument) -> tuple[str, float] | None:
    candidates = []
    for line in document.lines:
        text = re.sub(r"\s+", "", line.text)
        if (
            not DOSAGE_FORM_SUFFIX.search(text)
            or EXPIRY_LABEL.search(text)
            or PRODUCTION_LABEL.search(text)
            or NAME_EXCLUSION.search(text)
            or BARE_DOSAGE_FORM.fullmatch(text)
        ):
            continue
        xs = [point[0] for point in line.box]
        ys = [point[1] for point in line.box]
        area = (max(xs) - min(xs)) * (max(ys) - min(ys))
        candidates.append(((len(text), area, line.score), text, line.score))
    selected = max(candidates, key=lambda value: value[0], default=None)
    return None if selected is None else (selected[1], selected[2])


def extract_candidates(
    documents: tuple[OCRDocument, ...],
    *,
    reference_date: date | None = None,
) -> MedicineCandidates:
    values = {
        "medicine_name": "",
        "specification": "",
        "manufacturer": "",
        "batch_number": "",
    }
    confidence = {}
    production_date = None
    expiry_date = None

    for document in documents:
        if document.role == "front" and not values["medicine_name"]:
            selected_name = _medicine_name(document)
            if selected_name is not None:
                values["medicine_name"], confidence["medicine_name"] = (
                    selected_name
                )

        for window in build_text_windows(document):
            text = re.sub(r"\s+", "", window.text)
            specification = SPEC.search(text)
            if specification and not values["specification"]:
                values["specification"] = specification.group(1)
                confidence["specification"] = window.score

            manufacturer = MANUFACTURER.search(text)
            if manufacturer and not values["manufacturer"]:
                values["manufacturer"] = manufacturer.group(1)
                confidence["manufacturer"] = window.score

            batch = BATCH.search(text)
            if batch and not values["batch_number"]:
                values["batch_number"] = batch.group(1)
                confidence["batch_number"] = window.score

            if production_date is None:
                production_date = _labelled_date(
                    text,
                    PRODUCTION_LABEL,
                    allow_month_year=False,
                )
                if production_date:
                    confidence["production_date"] = window.score

            if expiry_date is None:
                expiry_date = _labelled_date(
                    text,
                    EXPIRY_LABEL,
                    allow_month_year=True,
                )
                if expiry_date:
                    confidence["expiry_date"] = window.score

    if production_date and expiry_date and production_date > expiry_date:
        production_date = None
        expiry_date = None
        confidence.pop("production_date", None)
        confidence.pop("expiry_date", None)
    if reference_date and production_date and production_date > reference_date:
        production_date = None
        confidence.pop("production_date", None)

    return MedicineCandidates(
        **values,
        production_date=production_date,
        expiry_date=expiry_date,
        confidence=confidence,
    )

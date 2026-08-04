import calendar
import re
from datetime import date

from .types import MedicineCandidates, OCRDocument


EXPIRY_LABEL = re.compile(r"有效期(?:至)?|失效期|EXP", re.IGNORECASE)
PRODUCTION_LABEL = re.compile(r"生产日期|生产日|MFG", re.IGNORECASE)
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
DOSAGE_FORM = re.compile(r"片|胶囊|颗粒|口服液|滴丸|喷雾|软膏|乳膏|糖浆")


def _month_end(year: int, month: int) -> date | None:
    try:
        return date(year, month, calendar.monthrange(year, month)[1])
    except ValueError:
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

    # 只解析标签后的日期，防止把生产日期误当成有效期。
    value = text[match.end() :]
    ymd = DATE_YMD.search(value)
    if ymd:
        year = int(ymd.group(1))
        month = int(ymd.group(2))
        if ymd.group(3):
            try:
                return date(year, month, int(ymd.group(3)))
            except ValueError:
                return None
        return _month_end(year, month)

    if allow_month_year:
        month_year = DATE_MY.search(value)
        if month_year:
            month = int(month_year.group(1))
            year = 2000 + int(month_year.group(2))
            return _month_end(year, month)
    return None


def extract_candidates(
    documents: tuple[OCRDocument, ...],
) -> MedicineCandidates:
    values = {
        "medicine_name": "",
        "specification": "",
        "batch_number": "",
    }
    confidence = {}
    production_date = None
    expiry_date = None

    for document in documents:
        for line in document.lines:
            text = re.sub(r"\s+", "", line.text)
            if (
                document.role == "front"
                and not values["medicine_name"]
                and DOSAGE_FORM.search(text)
                and not EXPIRY_LABEL.search(text)
                and not PRODUCTION_LABEL.search(text)
            ):
                values["medicine_name"] = text
                confidence["medicine_name"] = line.score

            specification = SPEC.search(text)
            if specification and not values["specification"]:
                values["specification"] = specification.group(1)
                confidence["specification"] = line.score

            batch = BATCH.search(text)
            if batch and not values["batch_number"]:
                values["batch_number"] = batch.group(1)
                confidence["batch_number"] = line.score

            if production_date is None:
                production_date = _labelled_date(
                    text,
                    PRODUCTION_LABEL,
                    allow_month_year=False,
                )
                if production_date:
                    confidence["production_date"] = line.score

            if expiry_date is None:
                expiry_date = _labelled_date(
                    text,
                    EXPIRY_LABEL,
                    allow_month_year=True,
                )
                if expiry_date:
                    confidence["expiry_date"] = line.score

    # 无标签日期保持为空，由用户手动确认，不能基于位置猜测。
    return MedicineCandidates(
        **values,
        production_date=production_date,
        expiry_date=expiry_date,
        confidence=confidence,
    )

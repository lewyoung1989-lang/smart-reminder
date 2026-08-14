import re
from decimal import Decimal, InvalidOperation


DOSE_PATTERN = re.compile(
    r"(?P<quantity>\d+(?:\.\d+)?|半|[零〇一二三四五六七八九十两]+)\s*"
    r"(?P<unit>mg|g|ml|毫克|克|毫升|片|粒|袋|支|丸|滴)",
    re.IGNORECASE,
)
UNIT_ALIASES = {
    "mg": "毫克",
    "g": "克",
    "ml": "毫升",
}
CHINESE_DIGITS = {
    "零": 0,
    "〇": 0,
    "一": 1,
    "二": 2,
    "两": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
}


def parse_structured_dose(text: str):
    match = DOSE_PATTERN.search(text)
    if match is None:
        return None, ""
    quantity = _parse_quantity(match.group("quantity"))
    if quantity is None or quantity <= 0:
        return None, ""
    raw_unit = match.group("unit").lower()
    return quantity, UNIT_ALIASES.get(raw_unit, raw_unit)


def _parse_quantity(value: str):
    if value == "半":
        return Decimal("0.5")
    try:
        return Decimal(value)
    except InvalidOperation:
        pass
    if "十" in value:
        tens, ones = value.split("十", maxsplit=1)
        tens_value = CHINESE_DIGITS.get(tens, 1) if tens else 1
        ones_value = CHINESE_DIGITS.get(ones, 0) if ones else 0
        return Decimal(tens_value * 10 + ones_value)
    if len(value) == 1 and value in CHINESE_DIGITS:
        return Decimal(CHINESE_DIGITS[value])
    return None

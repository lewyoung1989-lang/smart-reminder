import re


PHONE_PATTERN = re.compile(r"^1[3-9]\d{9}$")


class InvalidPhone(ValueError):
    pass


def normalize_mainland_phone(value: str) -> str:
    if not isinstance(value, str):
        raise InvalidPhone("invalid_phone")
    phone = value.strip()
    if not PHONE_PATTERN.fullmatch(phone):
        raise InvalidPhone("invalid_phone")
    return f"+86{phone}"


def mask_phone(phone_e164: str) -> str:
    phone = phone_e164.removeprefix("+86")
    if not PHONE_PATTERN.fullmatch(phone):
        raise InvalidPhone("invalid_phone")
    return f"{phone[:3]}****{phone[-4:]}"

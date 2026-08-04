import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from pydantic import BaseModel

from .schemas import Precheck, RainCondition, ReminderDraftData, Schedule


_TIME_PATTERN = re.compile(
    r"(?P<hour>[零〇一二三四五六七八九十两\d]{1,3})点"
    r"(?:(?P<half>半)|(?P<minute>[零〇一二三四五六七八九十两\d]{1,3})分?)?"
)
_RELATIVE_MINUTES_PATTERN = re.compile(
    r"(?P<minutes>[零〇一二三四五六七八九十两\d]{1,3})分钟后"
)
_DIGITS = {
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
_UNSUPPORTED_ACTIONS = ("删除", "停用", "关闭提醒", "标记已服")


class LocalParseResult(BaseModel):
    draft: ReminderDraftData
    requires_provider: bool = False


def _chinese_number(value: str) -> int:
    if value.isdigit():
        return int(value)
    if value == "十":
        return 10
    if "十" in value:
        tens, ones = value.split("十", maxsplit=1)
        tens_value = _DIGITS[tens] if tens else 1
        ones_value = _DIGITS[ones] if ones else 0
        return tens_value * 10 + ones_value
    if len(value) == 1 and value in _DIGITS:
        return _DIGITS[value]
    raise ValueError(f"unsupported Chinese number: {value}")


def _parse_day_and_time(text: str, now: datetime, timezone: str) -> datetime | None:
    match = _TIME_PATTERN.search(text)
    if match is None:
        return None

    hour = _chinese_number(match.group("hour"))
    minute_group = match.group("minute")
    minute = 30 if match.group("half") else _chinese_number(minute_group) if minute_group else 0
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        return None

    if "明天" in text:
        day_offset = 1
    elif "今天" in text:
        day_offset = 0
    else:
        return None

    local_now = now.astimezone(ZoneInfo(timezone))
    target_date = (local_now + timedelta(days=day_offset)).date()
    return datetime(
        target_date.year,
        target_date.month,
        target_date.day,
        hour,
        minute,
        tzinfo=ZoneInfo(timezone),
    )


def _weather_precheck(text: str) -> Precheck | None:
    if "雨" not in text and "带伞" not in text:
        return None
    return Precheck(
        minutes_before=20,
        condition=RainCondition(window_minutes=120, value=40),
    )


def _extract_title(text: str) -> str:
    for marker in ("提醒我", "叫我"):
        if marker in text:
            candidate = text.split(marker, maxsplit=1)[1]
            candidate = re.split(r"[，。,.；;]", candidate, maxsplit=1)[0].strip()
            if candidate:
                return candidate[:200]
    return "文字提醒"


def _unresolved(message: str) -> ReminderDraftData:
    return ReminderDraftData(
        title="提醒草稿",
        schedule=None,
        precheck=None,
        severity="notification",
        condition_met_message=None,
        ambiguities=[message],
    )


def parse_text_reminder(
    text: str,
    *,
    now: datetime,
    timezone: str,
) -> LocalParseResult:
    if any(action in text for action in _UNSUPPORTED_ACTIONS):
        return LocalParseResult(draft=_unresolved("首版只支持创建提醒"))

    relative_match = _RELATIVE_MINUTES_PATTERN.search(text)
    if relative_match is not None:
        minutes = _chinese_number(relative_match.group("minutes"))
        if minutes > 0:
            scheduled_at = now.astimezone(ZoneInfo(timezone)) + timedelta(minutes=minutes)
            return LocalParseResult(
                draft=ReminderDraftData(
                    title=_extract_title(text),
                    schedule=Schedule(local_datetime=scheduled_at, timezone=timezone),
                    precheck=None,
                    severity="notification",
                    condition_met_message=None,
                    ambiguities=[],
                )
            )

    scheduled_at = _parse_day_and_time(text, now, timezone)
    precheck = _weather_precheck(text)
    is_alarm = "起床" in text or "闹钟" in text
    draft = ReminderDraftData(
        title=(
            "起床并查看天气"
            if is_alarm and precheck
            else "起床提醒"
            if is_alarm
            else _extract_title(text)
        ),
        schedule=Schedule(local_datetime=scheduled_at, timezone=timezone) if scheduled_at else None,
        precheck=precheck,
        severity="alarm" if is_alarm else "notification",
        condition_met_message="未来两小时可能有雨，建议带伞" if precheck else None,
        ambiguities=[] if scheduled_at else ["缺少提醒时间"],
    )
    return LocalParseResult(draft=draft, requires_provider=scheduled_at is None)

import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from .schemas import Precheck, RainCondition, ReminderDraftData, Schedule


_TIME_PATTERN = re.compile(
    r"(?P<hour>[零〇一二三四五六七八九十两\d]{1,3})点"
    r"(?:(?P<half>半)|(?P<minute>[零〇一二三四五六七八九十两\d]{1,3})分?)?"
)
_DIGITS = {"零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


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


def _parse_day_and_time(transcript: str, now: datetime, timezone: str) -> datetime | None:
    match = _TIME_PATTERN.search(transcript)
    if match is None:
        return None

    hour = _chinese_number(match.group("hour"))
    minute_group = match.group("minute")
    minute = 30 if match.group("half") else _chinese_number(minute_group) if minute_group else 0
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        return None

    if "明天" in transcript:
        day_offset = 1
    elif "今天" in transcript:
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


def _weather_precheck(transcript: str) -> Precheck | None:
    if "雨" not in transcript and "带伞" not in transcript:
        return None
    window_minutes = 120 if "两小时" in transcript or "2小时" in transcript else 120
    return Precheck(
        minutes_before=20,
        condition=RainCondition(window_minutes=window_minutes, value=40),
    )


def parse_voice_reminder(
    transcript: str,
    *,
    now: datetime,
    timezone: str,
) -> ReminderDraftData:
    scheduled_at = _parse_day_and_time(transcript, now, timezone)
    precheck = _weather_precheck(transcript)
    is_alarm = "起床" in transcript or "闹钟" in transcript

    return ReminderDraftData(
        title="起床并查看天气" if is_alarm and precheck else "起床提醒" if is_alarm else "语音提醒",
        schedule=Schedule(local_datetime=scheduled_at, timezone=timezone) if scheduled_at else None,
        precheck=precheck,
        severity="alarm" if is_alarm else "notification",
        condition_met_message="未来两小时可能有雨，建议带伞" if precheck else None,
        ambiguities=[] if scheduled_at else ["缺少提醒时间"],
    )

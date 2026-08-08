"""Deterministic parsing for the fixed workflow templates."""

from __future__ import annotations

import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from apps.workflows.domain.schemas import TaskSpec


_URL_PATTERN = re.compile(r"[a-z][a-z0-9+.-]*://", re.IGNORECASE)
_DOSE_PATTERN = re.compile(r"\d+(?:\.\d+)?\s*(?:mg|g|ml|毫克|克|片|粒)", re.IGNORECASE)
_MEDICINE_PATTERN = re.compile(
    r"(?:吃药|服药|吃)\s*(?:[:：]\s*)?(?P<name>[\u4e00-\u9fffA-Za-z][\u4e00-\u9fffA-Za-z()（）-]{0,30})"
)
_MEDICINE_ID_PATTERN = re.compile(r"\b(?P<id>[A-Za-z][A-Za-z0-9_]*-\d+)\b")
_THRESHOLD_PATTERN = re.compile(r"提前\s*(?P<days>\d{1,3})\s*天")
_TIME_PATTERN = re.compile(
    r"(?P<hour>[零〇一二三四五六七八九十两\d]{1,3})点"
    r"(?:(?P<half>半)|(?P<minute>[零〇一二三四五六七八九十两\d]{1,3})分?)?"
)
_DESTINATION_PATTERN = re.compile(r"(?:到|去)\s*(?P<destination>[^，。,.；;]+)")
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


class WorkflowTaskParser:
    """Parse only complete requests that fit a registered workflow template."""

    def parse(self, text: str, now: datetime, timezone: str) -> TaskSpec:
        text = text.strip()
        if _URL_PATTERN.search(text):
            if any(marker in text for marker in ("到", "去", "出门", "公交")):
                return _clarification("目的地不能包含网址，请提供地点名称")
            return _clarification("请勿在请求中包含网址")

        medication = self._parse_medication(text)
        if medication is not None:
            return medication

        expiry = self._parse_expiry(text)
        if expiry is not None:
            return expiry

        departure = self._parse_departure(text, now=now, timezone=timezone)
        if departure is not None:
            return departure

        return _clarification("请说明要创建哪种提醒")

    @staticmethod
    def _parse_medication(text: str) -> TaskSpec | None:
        medication_match = _MEDICINE_PATTERN.search(text)
        medication_request = medication_match is not None or any(
            marker in text for marker in ("吃药", "服药")
        )
        if not medication_request:
            return None

        dose_match = _DOSE_PATTERN.search(text)
        frequency = "daily" if "每天" in text or "每日" in text else None
        if medication_match is None or dose_match is None or frequency is None:
            return _clarification("请补充药品剂量和服药周期")
        time_of_day = _parse_time_of_day(text)
        if time_of_day is None:
            return _clarification("请补充服药时间")

        return TaskSpec(
            template_hint="medication_cycle",
            title="用药提醒",
            slots={
                "medicine_name": medication_match.group("name"),
                "dose_text": dose_match.group(0).replace(" ", ""),
                "frequency": frequency,
                "time_of_day": time_of_day,
            },
            requested_capabilities=[
                "medicine.schedule",
                "notification.important",
            ],
        )

    @staticmethod
    def _parse_expiry(text: str) -> TaskSpec | None:
        if "有效期" not in text and "过期" not in text:
            return None

        medicine_id_match = _MEDICINE_ID_PATTERN.search(text)
        if medicine_id_match is None:
            return _clarification("请提供明确的药品ID")

        threshold_match = _THRESHOLD_PATTERN.search(text)
        threshold_days = int(threshold_match.group("days")) if threshold_match else 30
        return TaskSpec(
            template_hint="medicine_expiry",
            title="有效期提醒",
            slots={
                "medicine_id": medicine_id_match.group("id"),
                "threshold_days": threshold_days,
            },
            requested_capabilities=[
                "medicine.inventory",
                "notification.important",
            ],
        )

    @staticmethod
    def _parse_departure(
        text: str, *, now: datetime, timezone: str
    ) -> TaskSpec | None:
        departure_request = any(marker in text for marker in ("到", "去", "出门", "公交"))
        if not departure_request:
            return None

        destination_match = _DESTINATION_PATTERN.search(text)
        destination = (
            _destination_text(destination_match.group("destination"))
            if destination_match is not None
            else None
        )
        if destination is not None and _URL_PATTERN.search(destination):
            return _clarification("目的地不能包含网址，请提供地点名称")

        arrival_time = _parse_arrival_time(text, now=now, timezone=timezone)
        travel_mode = _travel_mode(text)
        if destination is None or arrival_time is None or travel_mode is None:
            return _clarification("请补充到达时间、目的地和出行方式")

        slots: dict[str, str] = {
            "arrival_time": arrival_time.isoformat(),
            "destination_text": destination,
            "travel_mode": travel_mode,
        }
        if "下雨" in text or "带伞" in text:
            slots["weather_advice"] = "rain"
        return TaskSpec(
            template_hint="smart_departure",
            title="智能出门提醒",
            slots=slots,
            requested_capabilities=[
                "route.estimate",
                "weather.forecast",
                "notification.important",
            ],
        )


def _clarification(question: str) -> TaskSpec:
    return TaskSpec(title="提醒草稿", ambiguities=[question])


def _parse_arrival_time(
    text: str, *, now: datetime, timezone: str
) -> datetime | None:
    time_match = _TIME_PATTERN.search(text)
    if time_match is None or (
        "今天" not in text and "明天" not in text and "明早" not in text
    ):
        return None

    hour = _chinese_number(time_match.group("hour"))
    minute_group = time_match.group("minute")
    minute = (
        30
        if time_match.group("half")
        else _chinese_number(minute_group)
        if minute_group
        else 0
    )
    if hour is None or minute is None or not 0 <= hour <= 23 or not 0 <= minute <= 59:
        return None

    local_timezone = ZoneInfo(timezone)
    local_now = now.replace(tzinfo=local_timezone) if now.tzinfo is None else now.astimezone(local_timezone)
    target_date = (
        local_now + timedelta(days=1 if "明天" in text or "明早" in text else 0)
    ).date()
    return datetime(
        target_date.year,
        target_date.month,
        target_date.day,
        hour,
        minute,
        tzinfo=local_timezone,
    )


def _parse_time_of_day(text: str) -> str | None:
    time_match = _TIME_PATTERN.search(text)
    if time_match is None:
        return None
    hour = _chinese_number(time_match.group("hour"))
    minute_group = time_match.group("minute")
    minute = (
        30
        if time_match.group("half")
        else _chinese_number(minute_group)
        if minute_group
        else 0
    )
    if hour is None or minute is None or not 0 <= hour <= 23 or not 0 <= minute <= 59:
        return None
    return f"{hour:02d}:{minute:02d}"


def _chinese_number(value: str) -> int | None:
    try:
        if value.isdigit():
            return int(value)
        if value == "十":
            return 10
        if "十" in value:
            tens, ones = value.split("十", maxsplit=1)
            tens_value = _DIGITS[tens] if tens else 1
            ones_value = _DIGITS[ones] if ones else 0
            return tens_value * 10 + ones_value
        return _DIGITS[value]
    except (KeyError, ValueError):
        return None


def _destination_text(value: str) -> str | None:
    end = len(value)
    for marker in ("坐公交", "公交", "坐地铁", "地铁", "开车", "驾车", "步行", "走路", "出门"):
        marker_index = value.find(marker)
        if marker_index >= 0:
            end = min(end, marker_index)
    destination = value[:end].strip()
    return destination or None


def _travel_mode(text: str) -> str | None:
    if "公交" in text or "地铁" in text:
        return "public_transit"
    if "开车" in text or "驾车" in text:
        return "driving"
    if "步行" in text or "走路" in text:
        return "walking"
    return None

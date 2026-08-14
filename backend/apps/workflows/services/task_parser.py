"""Deterministic parsing for the fixed workflow templates."""

from __future__ import annotations

import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from apps.workflows.domain.schemas import TaskSpec


_URL_PATTERN = re.compile(r"[a-z][a-z0-9+.-]*://", re.IGNORECASE)
_DOSE_PATTERN = re.compile(
    r"(?:\d+(?:\.\d+)?|半|[零〇一二三四五六七八九十两]+)\s*"
    r"(?:mg|g|ml|毫克|克|毫升|片|粒|袋|支|丸|滴)",
    re.IGNORECASE,
)
_MEDICINE_PATTERN = re.compile(
    r"(?:吃药|服药|吃)\s*(?:[:：]\s*)?(?P<name>[\u4e00-\u9fffA-Za-z][\u4e00-\u9fffA-Za-z()（）-]{0,30})"
)
_MEDICINE_AFTER_DAILY_COUNT_PATTERN = re.compile(
    r"(?:每天|每日|一天|一日)\s*(?:要|需|需要)?\s*(?:吃|服用|服药)?\s*"
    r"[零〇一二三四五六七八九十两\d]{1,3}\s*次[，,\s]*"
    r"(?:吃|服用|服药)?\s*"
    r"(?P<name>[\u4e00-\u9fffA-Za-z][\u4e00-\u9fffA-Za-z()（）-]{0,30})"
)
_MEDICINE_BEFORE_DAILY_PATTERN = re.compile(
    r"^(?P<name>[\u4e00-\u9fffA-Za-z][\u4e00-\u9fffA-Za-z()（）-]{0,30})"
    r"(?=(?:每天|每日|一天|一日))"
)
_MEDICINE_FALLBACK_STOP = re.compile(
    r"(?:吃药|服药|服用|提醒|长期|连续|每天|每日|一天|一次|一周|以后|今后|之后|开始"
    r"|早上|上午|中午|下午|晚上|睡前|饭前|饭后|记得|帮我|帮忙|需要|想要"
    r"|请|补充|的|我|是|要|想|从|药[品物]?)"
)
_MEDICINE_ID_PATTERN = re.compile(r"\b(?P<id>[A-Za-z][A-Za-z0-9_]*-\d+)\b")
_THRESHOLD_PATTERN = re.compile(r"提前\s*(?P<days>\d{1,3})\s*天")
_TIME_PATTERN = re.compile(
    r"(?P<hour>[零〇一二三四五六七八九十两\d]{1,3})点"
    r"(?:(?P<half>半)|(?P<minute>[零〇一二三四五六七八九十两\d]{1,3})分?)?"
)
_CLOCK_TIME_PATTERN = re.compile(
    r"(?<!\d)(?P<hour>[01]?\d|2[0-3])[:：](?P<minute>[0-5]\d)(?!\d)"
)
_DAILY_COUNT_PATTERN = re.compile(
    r"(?:每天|每日|一天|一日)\s*(?:要|需|需要)?\s*(?:吃|服用|服药)?\s*"
    r"(?P<count>[零〇一二三四五六七八九十两\d]{1,3})\s*次"
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
_GENERIC_MEDICINE_NAMES = {
    "药",
    "药品",
    "药物",
    "吃",
    "服用",
    "服药",
    "每次",
    "一次",
    "次",
}
_MEDICINE_NAME_MARKERS = (
    "药",
    "片",
    "丸",
    "散",
    "膏",
    "胶囊",
    "口服液",
    "滴眼液",
    "维生素",
    "头孢",
    "阿莫西林",
    "布洛芬",
)
_MEDICINE_NAME_SUFFIXES = (
    "芬",
    "林",
    "素",
    "敏",
    "唑",
    "酮",
    "平",
    "宁",
    "定",
    "沙星",
)


class WorkflowTaskParser:
    """Parse only complete requests that fit a registered workflow template."""

    def parse(self, text: str, now: datetime, timezone: str) -> TaskSpec:
        text = text.strip()
        if _URL_PATTERN.search(text):
            if any(marker in text for marker in ("到", "去", "出门", "公交")):
                return _clarification("目的地不能包含网址，请提供地点名称")
            return _clarification("请勿在请求中包含网址")

        expiry = self._parse_expiry(text)
        if expiry is not None:
            return expiry

        medication = self._parse_medication(text)
        if medication is not None:
            return medication

        departure = self._parse_departure(text, now=now, timezone=timezone)
        if departure is not None:
            return departure

        return _clarification("请说明要创建哪种提醒")

    @staticmethod
    def _parse_medication(text: str) -> TaskSpec | None:
        medication_matches = list(_MEDICINE_PATTERN.finditer(text))
        medicine_name = next(
            (
                match.group("name")
                for match in medication_matches
                if match.group("name") not in _GENERIC_MEDICINE_NAMES
            ),
            None,
        )
        if medicine_name is not None and re.fullmatch(
            r"[零〇一二三四五六七八九十两\d]+次", medicine_name
        ):
            medicine_name = None
        if medicine_name is None:
            positioned_match = _MEDICINE_BEFORE_DAILY_PATTERN.search(text)
            if positioned_match is None:
                positioned_match = _MEDICINE_AFTER_DAILY_COUNT_PATTERN.search(text)
            medicine_name = (
                positioned_match.group("name") if positioned_match is not None else None
            )
            if medicine_name is not None and (
                medicine_name.startswith(("每次", "一次"))
                or _MEDICINE_FALLBACK_STOP.fullmatch(medicine_name) is not None
                or medicine_name in _GENERIC_MEDICINE_NAMES
            ):
                medicine_name = None
        if medicine_name is None:
            medicine_name = _fallback_medicine_name(text)
        explicit_medication_request = any(
            marker in text for marker in ("吃药", "服药", "服用", "药")
        )
        dose_match = _DOSE_PATTERN.search(text)
        has_cycle_marker = any(
            marker in text
            for marker in ("每天", "每日", "一天", "一日", "长期", "连续")
        )
        medication_request = explicit_medication_request or (
            bool(medication_matches) and looks_like_medicine_name(medicine_name)
        ) or (
            bool(medication_matches) and dose_match is not None and has_cycle_marker
        ) or (
            dose_match is not None
            and has_cycle_marker
            and any(marker in text for marker in ("吃", "服用", "服药"))
        )
        if not medication_request:
            return None
        daily_count = _parse_daily_count(text)
        frequency = "daily" if daily_count is not None or any(
            marker in text
            for marker in ("每天", "每日", "一天", "一日", "长期", "连续")
        ) else None
        times = _parse_times_of_day(text)

        slots: dict[str, str | list[str]] = {}
        if medicine_name is not None:
            slots["medicine_name"] = medicine_name
        if dose_match is not None:
            slots["dose_text"] = dose_match.group(0).replace(" ", "")
        if frequency is not None:
            slots["frequency"] = frequency
        if times:
            # time_of_day remains for workflows created before multi-time support.
            slots["time_of_day"] = times[0]
            if len(times) > 1:
                slots["times"] = times

        if dose_match is None or frequency is None:
            return _clarification(
                "请补充药品剂量和服药周期",
                template_hint="medication_cycle",
                slots=slots,
            )
        if daily_count is not None and daily_count != len(times):
            return _clarification(
                f"请补充每天 {daily_count} 次的具体服药时间",
                template_hint="medication_cycle",
                slots=slots,
            )
        if not times:
            return _clarification(
                "请补充服药时间",
                template_hint="medication_cycle",
                slots=slots,
            )
        if medicine_name is None:
            return _clarification(
                "请补充药品名称",
                template_hint="medication_cycle",
                slots=slots,
            )

        return TaskSpec(
            template_hint="medication_cycle",
            title="用药提醒",
            slots=slots,
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
            return _clarification("请提供明确的药品ID", template_hint="medicine_expiry")

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
            return _clarification("目的地不能包含网址，请提供地点名称", template_hint="smart_departure")

        arrival_time = _parse_arrival_time(text, now=now, timezone=timezone)
        travel_mode = _travel_mode(text)
        if destination is None or arrival_time is None or travel_mode is None:
            partial: dict[str, str] = {}
            if destination is not None:
                partial["destination_text"] = destination
            if arrival_time is not None:
                partial["arrival_time"] = arrival_time.isoformat()
            if travel_mode is not None:
                partial["travel_mode"] = travel_mode
            return _clarification(
                "请补充到达时间、目的地和出行方式",
                template_hint="smart_departure",
                slots=partial,
            )

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


def _fallback_medicine_name(text: str) -> str | None:
    """Extract a bare medicine name when no 「吃/服」verb phrase matches.

    追问回复常只给药名（如「阿莫西林」或「阿莫西林1片」），先去掉剂量与
    时间表达，再切掉周期/动词等高频词，剩下的中文词即视为药名。
    """
    stripped = _DOSE_PATTERN.sub(" ", text)
    stripped = _TIME_PATTERN.sub(" ", stripped)
    stripped = _CLOCK_TIME_PATTERN.sub(" ", stripped)
    tokens: list[str] = []
    remainder = stripped
    while remainder:
        stop_match = _MEDICINE_FALLBACK_STOP.search(remainder)
        chunk, remainder = (
            (remainder[: stop_match.start()], remainder[stop_match.end():])
            if stop_match
            else (remainder, "")
        )
        tokens.extend(re.findall(r"[\u4e00-\u9fffA-Za-z()（）-]+", chunk))
    return next(
        (token for token in tokens if token not in _GENERIC_MEDICINE_NAMES),
        None,
    )


def looks_like_medicine_name(value: object) -> bool:
    if not isinstance(value, str):
        return False
    name = value.strip()
    if not name or name in _GENERIC_MEDICINE_NAMES:
        return False
    return any(marker in name for marker in _MEDICINE_NAME_MARKERS) or any(
        name.endswith(suffix) for suffix in _MEDICINE_NAME_SUFFIXES
    )


def _clarification(
    question: str,
    template_hint: str | None = None,
    slots: dict[str, str | list[str]] | None = None,
) -> TaskSpec:
    return TaskSpec(
        title="提醒草稿",
        template_hint=template_hint,
        slots=slots or {},
        ambiguities=[question],
    )


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
    if hour is not None:
        hour = _normalize_hour_for_period(text, time_match, hour)
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


def _parse_times_of_day(text: str) -> list[str]:
    parsed: list[tuple[int, str]] = []
    for time_match in _TIME_PATTERN.finditer(text):
        hour = _chinese_number(time_match.group("hour"))
        minute_group = time_match.group("minute")
        minute = (
            30
            if time_match.group("half")
            else _chinese_number(minute_group)
            if minute_group
            else 0
        )
        if hour is not None:
            hour = _normalize_hour_for_period(text, time_match, hour)
        if hour is None or minute is None or not 0 <= hour <= 23 or not 0 <= minute <= 59:
            continue
        parsed.append((time_match.start(), f"{hour:02d}:{minute:02d}"))
    for time_match in _CLOCK_TIME_PATTERN.finditer(text):
        parsed.append(
            (
                time_match.start(),
                f"{int(time_match.group('hour')):02d}:{int(time_match.group('minute')):02d}",
            )
        )

    times: list[str] = []
    for _, value in sorted(parsed):
        if value not in times:
            times.append(value)
    return sorted(times)


def _parse_time_of_day(text: str) -> str | None:
    times = _parse_times_of_day(text)
    return times[0] if times else None


def _parse_daily_count(text: str) -> int | None:
    match = _DAILY_COUNT_PATTERN.search(text)
    if match is None:
        return None
    count = _chinese_number(match.group("count"))
    return count if count is not None and count > 0 else None


def _normalize_hour_for_period(text: str, time_match: re.Match[str], hour: int) -> int:
    prefix = text[max(0, time_match.start() - 4) : time_match.start()]
    if any(marker in prefix for marker in ("下午", "晚上", "傍晚", "晚间", "夜里")):
        if 1 <= hour <= 11:
            return hour + 12
    if "中午" in prefix and 1 <= hour <= 2:
        return hour + 12
    return hour


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

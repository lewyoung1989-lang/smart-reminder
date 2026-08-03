from datetime import datetime
from zoneinfo import ZoneInfo

from apps.reminders.domain.voice_parser import parse_voice_reminder


NOW = datetime(2026, 8, 3, 10, 0, tzinfo=ZoneInfo("Asia/Shanghai"))


def test_parses_tomorrow_alarm_with_weather_condition():
    result = parse_voice_reminder(
        "明天早上七点半叫我起床，先查未来两小时天气，如果下雨提醒我带伞。",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.intent == "create_reminder"
    assert result.schedule is not None
    assert result.schedule.local_datetime.isoformat() == "2026-08-04T07:30:00+08:00"
    assert result.precheck is not None
    assert result.precheck.condition.window_minutes == 120
    assert result.precheck.condition.value == 40
    assert result.severity == "alarm"
    assert result.condition_met_message == "未来两小时可能有雨，建议带伞"
    assert result.ambiguities == []


def test_missing_time_returns_ambiguity_instead_of_guessing():
    result = parse_voice_reminder(
        "下雨提醒我带伞",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.schedule is None
    assert result.ambiguities == ["缺少提醒时间"]

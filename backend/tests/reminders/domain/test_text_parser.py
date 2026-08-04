from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from apps.reminders.domain.text_parser import parse_text_reminder


NOW = datetime(2026, 8, 4, 10, 0, tzinfo=ZoneInfo("Asia/Shanghai"))


def test_parses_relative_minute_reminder():
    result = parse_text_reminder(
        "1分钟后提醒我喝水",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.draft.title == "喝水"
    assert result.draft.schedule is not None
    assert result.draft.schedule.local_datetime == NOW + timedelta(minutes=1)
    assert result.draft.severity == "notification"
    assert result.draft.ambiguities == []
    assert result.requires_provider is False


def test_parses_chinese_relative_minute_reminder():
    result = parse_text_reminder(
        "十分钟后提醒我休息",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.draft.title == "休息"
    assert result.draft.schedule is not None
    assert result.draft.schedule.local_datetime == NOW + timedelta(minutes=10)


def test_delete_intent_is_not_executable():
    result = parse_text_reminder(
        "删除明天的提醒",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.draft.schedule is None
    assert result.draft.ambiguities == ["首版只支持创建提醒"]
    assert result.requires_provider is False


def test_unrecognized_single_reminder_requires_provider():
    result = parse_text_reminder(
        "下周一上午十点提醒我体检",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.draft.schedule is None
    assert result.requires_provider is True

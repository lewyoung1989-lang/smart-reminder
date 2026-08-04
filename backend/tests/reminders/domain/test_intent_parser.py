from datetime import datetime
from zoneinfo import ZoneInfo

from apps.reminders.domain.intent_parser import ReminderIntentParser
from apps.reminders.domain.schemas import ReminderDraftData, Schedule
from apps.reminders.providers.deepseek import DeepSeekResponseError


NOW = datetime(2026, 8, 4, 10, 0, tzinfo=ZoneInfo("Asia/Shanghai"))
MODEL_DRAFT = ReminderDraftData(
    title="体检",
    schedule=Schedule(
        local_datetime=datetime(2026, 8, 10, 10, 0, tzinfo=ZoneInfo("Asia/Shanghai")),
        timezone="Asia/Shanghai",
    ),
    precheck=None,
    severity="notification",
    condition_met_message=None,
    ambiguities=[],
)


class FailingIfCalledProvider:
    def parse(self, text, *, now, timezone):
        raise AssertionError("provider must not be called")


class FakeProvider:
    def __init__(self, draft):
        self.draft = draft

    def parse(self, text, *, now, timezone):
        return self.draft


class UnavailableProvider:
    def parse(self, text, *, now, timezone):
        raise DeepSeekResponseError("unavailable")


def test_confident_local_result_does_not_call_provider():
    result = ReminderIntentParser(FailingIfCalledProvider()).parse(
        "1分钟后提醒我喝水",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.source == "local"
    assert result.draft.title == "喝水"


def test_unresolved_local_result_uses_deepseek():
    result = ReminderIntentParser(FakeProvider(MODEL_DRAFT)).parse(
        "下周一上午十点提醒我体检",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.source == "deepseek"
    assert result.draft == MODEL_DRAFT


def test_provider_failure_returns_unconfirmed_draft():
    result = ReminderIntentParser(UnavailableProvider()).parse(
        "下周一上午十点提醒我体检",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.source == "local_fallback"
    assert result.draft.schedule is None
    assert result.draft.ambiguities == ["暂时无法理解，请换一种说法后重试"]


def test_missing_provider_returns_unconfirmed_local_draft():
    result = ReminderIntentParser().parse(
        "下周一上午十点提醒我体检",
        now=NOW,
        timezone="Asia/Shanghai",
    )

    assert result.source == "local_fallback"
    assert result.draft.schedule is None

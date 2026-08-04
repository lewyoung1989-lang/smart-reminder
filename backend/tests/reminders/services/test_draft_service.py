import hashlib
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from apps.reminders.domain.intent_parser import ParsedReminderIntent
from apps.reminders.domain.schemas import ReminderDraftData, Schedule
from apps.reminders.models import ReminderDraft, VoiceParseSession
from apps.reminders.services.draft_service import create_reminder_draft


NOW = datetime(2026, 8, 4, 10, 0, tzinfo=ZoneInfo("Asia/Shanghai"))
TEXT = "1分钟后提醒我喝水"


class FakeParser:
    def parse(self, text, *, now, timezone):
        return ParsedReminderIntent(
            draft=ReminderDraftData(
                title="喝水",
                schedule=Schedule(
                    local_datetime=datetime(
                        2026,
                        8,
                        4,
                        10,
                        1,
                        tzinfo=ZoneInfo("Asia/Shanghai"),
                    ),
                    timezone="Asia/Shanghai",
                ),
                precheck=None,
                severity="notification",
                condition_met_message=None,
                ambiguities=[],
            ),
            source="local",
        )


@pytest.mark.django_db
def test_service_stores_hash_source_and_structured_draft_without_raw_text(user):
    result = create_reminder_draft(
        user=user,
        text=TEXT,
        parser=FakeParser(),
        now=NOW,
        timezone="Asia/Shanghai",
    )

    session = VoiceParseSession.objects.get()
    draft = ReminderDraft.objects.get()
    assert result.draft == draft
    assert result.parser_source == "local"
    assert session.transcript_sha256 == hashlib.sha256(TEXT.encode()).hexdigest()
    assert session.parser_source == "local"
    assert not hasattr(session, "transcript")
    assert TEXT not in str(session.__dict__)
    assert draft.draft_json["title"] == "喝水"

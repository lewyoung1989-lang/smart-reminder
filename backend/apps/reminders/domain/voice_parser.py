from datetime import datetime

from .schemas import ReminderDraftData
from .text_parser import parse_text_reminder


def parse_voice_reminder(
    transcript: str,
    *,
    now: datetime,
    timezone: str,
) -> ReminderDraftData:
    return parse_text_reminder(
        transcript,
        now=now,
        timezone=timezone,
    ).draft

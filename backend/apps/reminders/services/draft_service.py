import hashlib
from dataclasses import dataclass
from datetime import datetime, timedelta

from django.db import transaction

from apps.reminders.domain.intent_parser import ReminderIntentParser
from apps.reminders.models import ReminderDraft, VoiceParseSession


@dataclass(frozen=True)
class CreatedReminderDraft:
    draft: ReminderDraft
    parser_source: str


def create_reminder_draft(
    *,
    user,
    text: str,
    parser: ReminderIntentParser,
    now: datetime,
    timezone: str,
) -> CreatedReminderDraft:
    parsed = parser.parse(text, now=now, timezone=timezone)
    return persist_reminder_draft(
        user=user,
        text=text,
        draft_data=parsed.draft,
        parser_source=parsed.source,
        now=now,
    )


def persist_reminder_draft(
    *,
    user,
    text: str,
    draft_data,
    parser_source: str,
    now: datetime,
) -> CreatedReminderDraft:
    expires_at = now + timedelta(minutes=15)
    draft_json = draft_data.model_dump(mode="json")

    with transaction.atomic():
        session = VoiceParseSession.objects.create(
            user=user,
            transcript_sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(),
            parser_source=parser_source,
            expires_at=expires_at,
        )
        draft = ReminderDraft.objects.create(
            session=session,
            draft_json=draft_json,
            ambiguities_json=draft_data.ambiguities,
            expires_at=expires_at,
        )
    return CreatedReminderDraft(draft=draft, parser_source=parser_source)

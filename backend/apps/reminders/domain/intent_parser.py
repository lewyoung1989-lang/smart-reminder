from dataclasses import dataclass
from datetime import datetime
from typing import Literal, Protocol

from apps.reminders.providers.deepseek import DeepSeekResponseError

from .schemas import ReminderDraftData
from .text_parser import parse_text_reminder


class ReminderIntentProvider(Protocol):
    def parse(
        self,
        text: str,
        *,
        now: datetime,
        timezone: str,
    ) -> ReminderDraftData: ...


@dataclass(frozen=True)
class ParsedReminderIntent:
    draft: ReminderDraftData
    source: Literal["local", "deepseek", "local_fallback"]


class ReminderIntentParser:
    def __init__(self, provider: ReminderIntentProvider | None = None):
        self.provider = provider

    def parse(
        self,
        text: str,
        *,
        now: datetime,
        timezone: str,
    ) -> ParsedReminderIntent:
        local = parse_text_reminder(text, now=now, timezone=timezone)
        if not local.requires_provider:
            return ParsedReminderIntent(local.draft, "local")

        if self.provider is None:
            return ParsedReminderIntent(
                self._fallback_draft(local.draft),
                "local_fallback",
            )

        try:
            model_draft = self.provider.parse(text, now=now, timezone=timezone)
        except DeepSeekResponseError:
            return ParsedReminderIntent(
                self._fallback_draft(local.draft),
                "local_fallback",
            )
        return ParsedReminderIntent(model_draft, "deepseek")

    @staticmethod
    def _fallback_draft(draft: ReminderDraftData) -> ReminderDraftData:
        return draft.model_copy(
            update={"ambiguities": ["暂时无法理解，请换一种说法后重试"]}
        )

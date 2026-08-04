import json
from datetime import datetime
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import ValidationError

from apps.reminders.domain.schemas import ReminderDraftData


class DeepSeekResponseError(Exception):
    pass


class JsonTransport(Protocol):
    def post_json(
        self,
        url: str,
        *,
        headers: dict[str, str],
        payload: dict[str, Any],
        timeout: float,
    ) -> dict[str, Any]: ...


class UrllibJsonTransport:
    def post_json(
        self,
        url: str,
        *,
        headers: dict[str, str],
        payload: dict[str, Any],
        timeout: float,
    ) -> dict[str, Any]:
        request = Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
            raise DeepSeekResponseError("DeepSeek request failed") from error


class DeepSeekReminderIntentProvider:
    def __init__(
        self,
        *,
        api_key: str,
        base_url: str = "https://api.deepseek.com",
        model: str = "deepseek-v4-flash",
        timeout_seconds: float = 8,
        transport: JsonTransport | None = None,
    ):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.transport = transport or UrllibJsonTransport()

    def parse(
        self,
        text: str,
        *,
        now: datetime,
        timezone: str,
    ) -> ReminderDraftData:
        if not self.api_key:
            raise DeepSeekResponseError("DeepSeek is not configured")

        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "system",
                    "content": self._system_prompt(now=now, timezone=timezone),
                },
                {"role": "user", "content": text},
            ],
            "response_format": {"type": "json_object"},
            "thinking": {"type": "disabled"},
            "temperature": 0,
            "max_tokens": 800,
            "stream": False,
        }
        response = self.transport.post_json(
            f"{self.base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            payload=payload,
            timeout=self.timeout_seconds,
        )

        try:
            content = response["choices"][0]["message"]["content"]
            raw_draft = json.loads(content)
            draft = ReminderDraftData.model_validate(raw_draft)
        except (KeyError, IndexError, TypeError, json.JSONDecodeError, ValidationError) as error:
            raise DeepSeekResponseError("DeepSeek returned an invalid reminder draft") from error

        draft = self._localize_naive_datetime(draft, timezone=timezone)
        self._validate_draft(draft, now=now, timezone=timezone)
        return draft

    @staticmethod
    def _localize_naive_datetime(
        draft: ReminderDraftData,
        *,
        timezone: str,
    ) -> ReminderDraftData:
        schedule = draft.schedule
        if (
            schedule is None
            or schedule.local_datetime.tzinfo is not None
            or schedule.timezone != timezone
        ):
            return draft
        try:
            local_datetime = schedule.local_datetime.replace(tzinfo=ZoneInfo(timezone))
        except ZoneInfoNotFoundError as error:
            raise DeepSeekResponseError(
                "DeepSeek returned an invalid reminder timezone"
            ) from error
        return draft.model_copy(
            update={
                "schedule": schedule.model_copy(
                    update={"local_datetime": local_datetime}
                )
            }
        )

    @staticmethod
    def _system_prompt(*, now: datetime, timezone: str) -> str:
        schema = json.dumps(ReminderDraftData.model_json_schema(), ensure_ascii=False)
        return (
            "你是提醒语义解析器，只允许创建提醒，不得删除、修改、停用提醒或执行状态操作。"
            "只输出一个 JSON 对象，禁止 Markdown。无法确定的内容必须写入 ambiguities，禁止猜测。"
            f"当前时间：{now.isoformat()}，时区：{timezone}。"
            "schedule.timezone 必须与给定时区完全一致，时间必须晚于当前时间。"
            f"输出必须严格符合此 JSON Schema：{schema}"
        )

    @staticmethod
    def _validate_draft(
        draft: ReminderDraftData,
        *,
        now: datetime,
        timezone: str,
    ) -> None:
        schedule = draft.schedule
        if schedule is None:
            if not draft.ambiguities:
                raise DeepSeekResponseError("DeepSeek returned an incomplete reminder draft")
            return
        if schedule.timezone != timezone:
            raise DeepSeekResponseError("DeepSeek returned an invalid reminder timezone")
        if schedule.local_datetime.tzinfo is None or schedule.local_datetime <= now:
            raise DeepSeekResponseError("DeepSeek returned an invalid reminder time")

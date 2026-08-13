import json
from datetime import datetime

from pydantic import ValidationError

from apps.reminders.domain.natural_language import NaturalLanguageDraft

from .deepseek import DeepSeekReminderIntentProvider, DeepSeekResponseError


class DeepSeekNaturalLanguageProvider(DeepSeekReminderIntentProvider):
    """将自然语言映射为提醒草稿或已注册工作流的安全输入。"""

    def parse(self, text: str, *, now: datetime, timezone: str) -> NaturalLanguageDraft:
        if not self.api_key:
            raise DeepSeekResponseError("DeepSeek is not configured")
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self._router_prompt(now, timezone)},
                {"role": "user", "content": text},
            ],
            "response_format": {"type": "json_object"},
            "thinking": {"type": "disabled"},
            "temperature": 0,
            "max_tokens": 1000,
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
            result = NaturalLanguageDraft.model_validate_json(content)
        except (KeyError, IndexError, TypeError, ValidationError) as error:
            raise DeepSeekResponseError("DeepSeek returned an invalid natural language draft") from error

        if result.reminder is not None:
            reminder = self._localize_naive_datetime(result.reminder, timezone=timezone)
            self._validate_draft(reminder, now=now, timezone=timezone)
            return result.model_copy(update={"reminder": reminder})
        return result

    @staticmethod
    def _router_prompt(now: datetime, timezone: str) -> str:
        schema = json.dumps(NaturalLanguageDraft.model_json_schema(), ensure_ascii=False)
        return (
            "你是智能提醒的自然语言路由器，只负责生成候选草稿，绝不执行任何动作。"
            "输出只能是单次提醒 reminder，或以下三种注册工作流之一："
            "medication_cycle、medicine_expiry、smart_departure。"
            "工作流只返回 TaskSpec 的意图和槽位，禁止生成节点、URL、代码、数据库动作或权限字段。"
            "medication_cycle 允许槽位 medicine_name、dose_text、frequency、time_of_day；"
            "medicine_expiry 允许 medicine_id、threshold_days；"
            "smart_departure 允许 arrival_time、destination_text、travel_mode、weather_advice。"
            "对应能力必须分别严格使用："
            "medicine.schedule 与 notification.important；"
            "medicine.inventory 与 notification.important；"
            "route.estimate、weather.forecast 与 notification.important。"
            "信息不足时保留已确定槽位，并把一个简短追问写入 ambiguities，禁止猜测。"
            "普通一次性事项必须选择 reminder。只允许创建，禁止删除、修改、停用或标记完成。"
            f"当前时间：{now.isoformat()}，时区：{timezone}。所有时间必须晚于当前时间。"
            "只输出 JSON 对象，禁止 Markdown。"
            f"输出必须严格符合此 JSON Schema：{schema}"
        )

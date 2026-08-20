import json
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from apps.reminders.providers.deepseek import DeepSeekResponseError
from apps.reminders.providers.natural_language import DeepSeekNaturalLanguageProvider


NOW = datetime(2026, 8, 13, 9, 0, tzinfo=ZoneInfo("Asia/Shanghai"))


class RecordingTransport:
    def __init__(self, value):
        self.value = value
        self.payload = None

    def post_json(self, url, *, headers, payload, timeout):
        self.payload = payload
        return {
            "choices": [
                {"message": {"content": json.dumps(self.value, ensure_ascii=False)}}
            ]
        }


def test_model_routes_to_registered_workflow_task_without_nodes():
    transport = RecordingTransport(
        {
            "draft_type": "workflow",
            "reminder": None,
            "workflow": {
                "schema_version": 1,
                "intent": "create_workflow",
                "template_hint": "medication_cycle",
                "title": "用药提醒",
                "slots": {
                    "medicine_name": "测试药品A",
                    "dose_text": "1片",
                    "frequency": "daily",
                    "time_of_day": "20:00",
                },
                "requested_capabilities": [
                    "medicine.schedule",
                    "notification.important",
                ],
                "ambiguities": [],
            },
        }
    )
    provider = DeepSeekNaturalLanguageProvider(api_key="test-key", transport=transport)

    result = provider.parse("每天晚上八点使用测试药品A一片", now=NOW, timezone="Asia/Shanghai")

    assert result.workflow.template_hint == "medication_cycle"
    assert "nodes" not in result.workflow.model_dump()
    prompt = transport.payload["messages"][0]["content"]
    assert "禁止生成节点" in prompt
    assert "用 times 数组保存全部时刻" in prompt


@pytest.mark.parametrize(
    "value",
    [
        {
            "draft_type": "workflow",
            "reminder": None,
            "workflow": {
                "template_hint": "medication_cycle",
                "title": "用药提醒",
                "slots": {},
                "requested_capabilities": [],
                "ambiguities": ["请补充信息"],
                "nodes": [{"type": "execute.shell"}],
            },
        },
        {"draft_type": "reminder", "reminder": None, "workflow": None},
    ],
)
def test_rejects_untrusted_or_inconsistent_model_output(value):
    provider = DeepSeekNaturalLanguageProvider(
        api_key="test-key", transport=RecordingTransport(value)
    )

    with pytest.raises(DeepSeekResponseError):
        provider.parse("测试输入", now=NOW, timezone="Asia/Shanghai")

import json
from datetime import date

import pytest

from apps.medicines.providers.deepseek import (
    DeepSeekMedicineDescriptionError,
    DeepSeekMedicineDescriptionProvider,
)


class RecordingTransport:
    def __init__(self, response):
        self.response = response
        self.url = None
        self.headers = None
        self.payload = None

    def post_json(self, url, *, headers, payload, timeout):
        self.url = url
        self.headers = headers
        self.payload = payload
        return self.response


def _completion(value):
    return {
        "choices": [
            {"message": {"content": json.dumps(value, ensure_ascii=False)}}
        ]
    }


def test_parses_description_as_strict_draft_without_executing():
    transport = RecordingTransport(
        _completion(
            {
                "medicine_name": "布洛芬胶囊",
                "specification": "0.3g*20粒",
                "batch_number": None,
                "production_date": None,
                "expiry_date": "2027-01-01",
                "quantity": 2,
                "ambiguities": ["批号未提供"],
            }
        )
    )
    provider = DeepSeekMedicineDescriptionProvider(
        api_key="test-key",
        transport=transport,
    )

    draft = provider.parse(
        "家里还有两盒布洛芬胶囊，每盒20粒每粒0.3克，明年元旦到期",
        today=date(2026, 8, 12),
    )

    assert draft.medicine_name == "布洛芬胶囊"
    assert draft.quantity == 2
    assert draft.expiry_date == date(2027, 1, 1)
    assert transport.payload["response_format"] == {"type": "json_object"}
    assert transport.payload["thinking"] == {"type": "disabled"}
    assert "不执行任何写入" in transport.payload["messages"][0]["content"]


@pytest.mark.parametrize(
    "value",
    [
        {
            "medicine_name": "布洛芬",
            "specification": None,
            "batch_number": None,
            "production_date": None,
            "expiry_date": None,
            "quantity": 0,
            "ambiguities": [],
        },
        {
            "medicine_name": None,
            "specification": None,
            "batch_number": None,
            "production_date": None,
            "expiry_date": None,
            "quantity": None,
            "ambiguities": [],
        },
        {
            "medicine_name": "布洛芬",
            "specification": None,
            "batch_number": None,
            "production_date": None,
            "expiry_date": None,
            "quantity": 1,
            "ambiguities": [],
            "execute": True,
        },
    ],
)
def test_rejects_untrusted_model_output(value):
    provider = DeepSeekMedicineDescriptionProvider(
        api_key="test-key",
        transport=RecordingTransport(_completion(value)),
    )

    with pytest.raises(DeepSeekMedicineDescriptionError) as captured:
        provider.parse("输入内容", today=date(2026, 8, 12))

    assert str(captured.value) == "medicine_description_invalid_response"

import json

import pytest

from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.providers.deepseek import (
    DeepSeekMedicineError,
    DeepSeekMedicineProvider,
    UrllibJsonTransport,
)


class RecordingTransport:
    def __init__(self, response):
        self.response = response
        self.payload = None

    def post_json(self, url, *, headers, payload, timeout):
        self.payload = payload
        return self.response


def _line(text, score=0.95):
    return OCRLine(((0, 0), (1, 0), (1, 1), (0, 1)), text, score)


def _completion(value):
    return {
        "choices": [
            {"message": {"content": json.dumps(value, ensure_ascii=False)}}
        ]
    }


def _empty_result(**overrides):
    value = {
        "medicine_name": None,
        "specification": None,
        "batch_number": None,
        "production_date_text": None,
        "expiry_date_text": None,
        "ambiguities": [],
    }
    value.update(overrides)
    return value


def test_provider_returns_only_fields_supported_by_evidence():
    transport = RecordingTransport(
        _completion(
            _empty_result(
                medicine_name={
                    "value": "阿莫西林胶囊",
                    "line_ids": ["front:1"],
                },
                expiry_date_text={
                    "value": "202805",
                    "line_ids": ["expiry:1"],
                },
            )
        )
    )
    provider = DeepSeekMedicineProvider(
        api_key="test-key",
        transport=transport,
    )

    result = provider.parse(
        (
            OCRDocument(
                "front",
                (
                    _line("每片中阿莫西林含量0.25g"),
                    _line("阿莫西林胶囊"),
                ),
            ),
            OCRDocument("expiry", (_line("有效期至"), _line("202805"))),
        )
    )

    assert result.medicine_name.value == "阿莫西林胶囊"
    assert result.expiry_date_text.value == "202805"
    assert transport.payload["response_format"] == {"type": "json_object"}
    assert "禁止猜测" in transport.payload["messages"][0]["content"]
    assert "image" not in transport.payload["messages"][1]["content"]


def test_provider_drops_a_field_not_present_in_evidence():
    transport = RecordingTransport(
        _completion(
            _empty_result(
                medicine_name={
                    "value": "图片中不存在的药名",
                    "line_ids": ["front:0"],
                }
            )
        )
    )
    provider = DeepSeekMedicineProvider(api_key="test-key", transport=transport)

    result = provider.parse(
        (OCRDocument("front", (_line("阿莫西林胶囊"),)),)
    )

    assert result.medicine_name is None


@pytest.mark.parametrize(
    "line_ids",
    [
        ["front:0", "front:2"],
        ["front:0", "expiry:0"],
    ],
)
def test_provider_drops_non_adjacent_or_cross_role_evidence(line_ids):
    transport = RecordingTransport(
        _completion(
            _empty_result(
                medicine_name={
                    "value": "阿莫西林胶囊",
                    "line_ids": line_ids,
                }
            )
        )
    )
    provider = DeepSeekMedicineProvider(api_key="test-key", transport=transport)

    result = provider.parse(
        (
            OCRDocument(
                "front",
                (_line("阿莫西林"), _line("说明文字"), _line("胶囊")),
            ),
            OCRDocument("expiry", (_line("胶囊"),)),
        )
    )

    assert result.medicine_name is None


def test_provider_rejects_unknown_json_fields_without_leaking_response():
    transport = RecordingTransport(
        _completion(
            {
                **_empty_result(),
                "unexpected": "private-upstream-response",
            }
        )
    )
    provider = DeepSeekMedicineProvider(api_key="test-key", transport=transport)

    with pytest.raises(DeepSeekMedicineError) as captured:
        provider.parse((OCRDocument("front", (_line("阿莫西林胶囊"),)),))

    assert str(captured.value) == "medicine_semantic_invalid_response"
    assert "private-upstream-response" not in str(captured.value)


@pytest.mark.parametrize(
    "transport_error",
    [
        TimeoutError("private-timeout-detail"),
        OSError("private-network-detail"),
    ],
)
def test_transport_wraps_network_errors_without_leaking_authorization(
    monkeypatch,
    transport_error,
):
    def timeout(*args, **kwargs):
        raise transport_error

    monkeypatch.setattr("apps.ocr.providers.deepseek.urlopen", timeout)
    transport = UrllibJsonTransport()

    with pytest.raises(DeepSeekMedicineError) as captured:
        transport.post_json(
            "https://api.deepseek.com/chat/completions",
            headers={"Authorization": "Bearer private-api-key"},
            payload={},
            timeout=1,
        )

    assert str(captured.value) == "medicine_semantic_request_failed"
    assert "private-api-key" not in str(captured.value)
    assert "private" not in str(captured.value)


def test_transport_wraps_invalid_utf8_response(monkeypatch):
    class InvalidResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc_value, traceback):
            return False

        def read(self):
            return b"\xff"

    monkeypatch.setattr(
        "apps.ocr.providers.deepseek.urlopen",
        lambda *args, **kwargs: InvalidResponse(),
    )

    with pytest.raises(DeepSeekMedicineError) as captured:
        UrllibJsonTransport().post_json(
            "https://api.deepseek.com/chat/completions",
            headers={},
            payload={},
            timeout=1,
        )

    assert str(captured.value) == "medicine_semantic_request_failed"

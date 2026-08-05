import json
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from pydantic import ValidationError

from apps.ocr.domain.semantic import EvidenceField, MedicineSemanticData
from apps.ocr.domain.types import OCRDocument


class DeepSeekMedicineError(Exception):
    pass


class JsonTransport(Protocol):
    def post_json(
        self,
        url: str,
        *,
        headers: dict[str, str],
        payload: dict[str, Any],
        timeout: float,
    ) -> dict[str, Any]:
        raise NotImplementedError


class UrllibJsonTransport:
    def post_json(self, url, *, headers, payload, timeout):
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
            raise DeepSeekMedicineError(
                "medicine_semantic_request_failed"
            ) from error


class DeepSeekMedicineProvider:
    FIELD_NAMES = (
        "medicine_name",
        "specification",
        "batch_number",
        "production_date_text",
        "expiry_date_text",
    )

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

    @staticmethod
    def _supported(
        field: EvidenceField | None,
        lines: dict[str, str],
    ) -> EvidenceField | None:
        if field is None or any(
            line_id not in lines for line_id in field.line_ids
        ):
            return None
        references = [line_id.rsplit(":", 1) for line_id in field.line_ids]
        roles = {role for role, index in references}
        try:
            indices = [int(index) for role, index in references]
        except ValueError:
            return None
        if len(roles) != 1 or indices != list(
            range(indices[0], indices[0] + len(indices))
        ):
            return None
        evidence = "".join(lines[line_id] for line_id in field.line_ids)
        normalized_evidence = "".join(evidence.split())
        normalized_value = "".join(field.value.split())
        return field if normalized_value in normalized_evidence else None

    @staticmethod
    def _system_prompt() -> str:
        schema = json.dumps(
            MedicineSemanticData.model_json_schema(),
            ensure_ascii=False,
        )
        return (
            "你是药盒 OCR 字段整理器，只能引用输入行中的原文。"
            "药名必须是具体药品名称，不能选择成分说明、用法、含量句或纯剂型。"
            "日期字段只返回图片中的原始日期文字，禁止补全、推断或改写。"
            "每个非空字段必须给出 line_ids；无法确定时返回 null 并写入 ambiguities。"
            "只输出符合给定 JSON Schema 的 JSON 对象，禁止 Markdown，禁止猜测。"
            f"输出必须符合此 JSON Schema：{schema}"
        )

    def parse(
        self,
        documents: tuple[OCRDocument, ...],
    ) -> MedicineSemanticData:
        if not self.api_key:
            raise DeepSeekMedicineError("medicine_semantic_not_configured")
        lines = {}
        input_lines = []
        for document in documents:
            for index, line in enumerate(document.lines):
                line_id = f"{document.role}:{index}"
                lines[line_id] = line.text
                input_lines.append(
                    {
                        "id": line_id,
                        "text": line.text,
                        "score": round(line.score, 5),
                    }
                )
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self._system_prompt()},
                {
                    "role": "user",
                    "content": json.dumps(input_lines, ensure_ascii=False),
                },
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
            parsed = MedicineSemanticData.model_validate_json(content)
        except (KeyError, IndexError, TypeError, ValidationError) as error:
            raise DeepSeekMedicineError(
                "medicine_semantic_invalid_response"
            ) from error
        return parsed.model_copy(
            update={
                name: self._supported(getattr(parsed, name), lines)
                for name in self.FIELD_NAMES
            }
        )

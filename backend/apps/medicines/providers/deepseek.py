import json
from datetime import date
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from pydantic import ValidationError

from apps.medicines.domain import MedicineDescriptionDraft


class DeepSeekMedicineDescriptionError(Exception):
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
        except (
            HTTPError,
            URLError,
            OSError,
            UnicodeDecodeError,
            json.JSONDecodeError,
        ) as error:
            raise DeepSeekMedicineDescriptionError(
                "medicine_description_request_failed"
            ) from error


class DeepSeekMedicineDescriptionProvider:
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

    def parse(self, text: str, *, today: date) -> MedicineDescriptionDraft:
        if not self.api_key:
            raise DeepSeekMedicineDescriptionError(
                "medicine_description_not_configured"
            )
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self._system_prompt(today=today)},
                {"role": "user", "content": text},
            ],
            "response_format": {"type": "json_object"},
            "thinking": {"type": "disabled"},
            "temperature": 0,
            "max_tokens": 600,
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
            return MedicineDescriptionDraft.model_validate_json(content)
        except (KeyError, IndexError, TypeError, ValidationError) as error:
            raise DeepSeekMedicineDescriptionError(
                "medicine_description_invalid_response"
            ) from error

    @staticmethod
    def _system_prompt(*, today: date) -> str:
        schema = json.dumps(
            MedicineDescriptionDraft.model_json_schema(),
            ensure_ascii=False,
        )
        return (
            "你是家庭药箱录入描述解析器。只负责提取用户明确表达的药品名称、"
            "规格、批号、生产日期、有效期和库存数量，不执行任何写入或其他操作。"
            f"今天是 {today.isoformat()}，可据此解析用户明确说出的相对日期。"
            "日期统一输出 YYYY-MM-DD。数量表示库存包装或物品数量，不是每盒片数；"
            "例如‘0.3g*20粒，2盒’的 quantity 是 2。"
            "缺失或无法确定的字段必须返回 null，并将需要用户确认的问题写入"
            " ambiguities，禁止猜测。只输出 JSON 对象，禁止 Markdown。"
            f"输出必须严格符合此 JSON Schema：{schema}"
        )

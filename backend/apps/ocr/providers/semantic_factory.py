from django.conf import settings

from .deepseek import DeepSeekMedicineProvider


def get_medicine_semantic_provider():
    provider = getattr(settings, "OCR_SEMANTIC_PROVIDER", "none")
    if provider == "none":
        return None
    if provider == "deepseek":
        return DeepSeekMedicineProvider(
            api_key=settings.DEEPSEEK_API_KEY,
            base_url=settings.DEEPSEEK_BASE_URL,
            model=settings.DEEPSEEK_MODEL,
            timeout_seconds=getattr(
                settings,
                "OCR_SEMANTIC_TIMEOUT_SECONDS",
                settings.DEEPSEEK_TIMEOUT_SECONDS,
            ),
        )
    raise ValueError("unsupported_ocr_semantic_provider")

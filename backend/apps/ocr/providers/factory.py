from django.conf import settings


def get_ocr_provider():
    if settings.OCR_PROVIDER == "rapidocr":
        # 惰性加载原生 OCR 依赖，避免 API 进程初始化模型并占用额外内存。
        from .rapidocr import RapidOCRProvider

        return RapidOCRProvider()
    raise ValueError(f"Unsupported OCR provider: {settings.OCR_PROVIDER}")

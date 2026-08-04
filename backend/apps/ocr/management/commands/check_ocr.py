import time
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from apps.ocr.providers.factory import get_ocr_provider


class Command(BaseCommand):
    help = "Load the configured OCR model and recognize a safe fixture"

    def add_arguments(self, parser):
        parser.add_argument("image_path")

    def handle(self, *args, **options):
        image_path = Path(options["image_path"])
        if not image_path.is_file():
            raise CommandError("OCR smoke fixture does not exist")

        started = time.monotonic()
        result = get_ocr_provider().recognize(
            image_path.read_bytes(),
            role="front",
        )
        if not result.lines:
            raise CommandError("OCR smoke check returned no lines")

        elapsed_ms = int((time.monotonic() - started) * 1000)
        # 冒烟输出只包含数量和耗时，不能打印合成图或真实药盒的识别文字。
        self.stdout.write(
            f"OCR smoke check passed: {len(result.lines)} lines; "
            f"{elapsed_ms} ms"
        )

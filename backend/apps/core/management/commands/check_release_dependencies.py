import urllib.request
import uuid
from urllib.parse import urljoin

from django.conf import settings
from django.core.cache import cache
from django.core.management.base import BaseCommand, CommandError
from django.db import connection


class Command(BaseCommand):
    help = "Check candidate API dependencies before replacing production."

    def handle(self, *args, **options):
        try:
            self._check_database()
            self._check_redis_cache()
            self._check_funasr()
        except Exception:
            raise CommandError(
                "Release dependency preflight failed"
            ) from None
        self.stdout.write("Release dependency preflight passed")

    @staticmethod
    def _check_database():
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            if cursor.fetchone() != (1,):
                raise RuntimeError("database probe failed")

    @staticmethod
    def _check_redis_cache():
        marker = uuid.uuid4().hex
        key = f"release-preflight:{marker}"
        try:
            cache.set(key, marker, timeout=30)
            if cache.get(key) != marker:
                raise RuntimeError("cache probe failed")
        finally:
            cache.delete(key)

    @staticmethod
    def _check_funasr():
        health_url = urljoin(
            settings.ASR_BASE_URL.rstrip("/") + "/", "health"
        )
        with urllib.request.urlopen(health_url, timeout=3) as response:
            if response.status != 200:
                raise RuntimeError("FunASR probe failed")

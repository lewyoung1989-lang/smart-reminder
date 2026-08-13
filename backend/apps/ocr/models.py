import uuid
from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone


def default_expiry():
    return timezone.now() + timedelta(hours=settings.OCR_JOB_RETENTION_HOURS)


class OCRJob(models.Model):
    class Status(models.TextChoices):
        QUEUED = "queued"
        RUNNING = "running"
        SUCCEEDED = "succeeded"
        FAILED = "failed"
        CONFIRMED = "confirmed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.QUEUED,
    )
    image_keys = models.JSONField()
    provider = models.CharField(max_length=32, default="rapidocr")
    attempt_count = models.PositiveSmallIntegerField(default=0)
    error_code = models.CharField(max_length=64, blank=True)
    confirmed_batch = models.OneToOneField(
        "medicines.InventoryBatch",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    expires_at = models.DateTimeField(default=default_expiry)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class OCRCandidate(models.Model):
    job = models.OneToOneField(
        OCRJob,
        on_delete=models.CASCADE,
        related_name="candidate",
    )
    medicine_name = models.CharField(max_length=200, blank=True)
    specification = models.CharField(max_length=120, blank=True)
    manufacturer = models.CharField(max_length=200, blank=True)
    batch_number = models.CharField(max_length=100, blank=True)
    production_date = models.DateField(null=True, blank=True)
    expiry_date = models.DateField(null=True, blank=True)
    confidence_json = models.JSONField(default=dict)
    raw_line_count = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

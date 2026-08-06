from datetime import timedelta

import pytest
from django.utils import timezone

from apps.ocr.models import OCRCandidate, OCRJob


@pytest.mark.django_db
def test_job_defaults_to_queued_and_expires_in_24_hours(user):
    before = timezone.now() + timedelta(hours=23, minutes=59)
    job = OCRJob.objects.create(
        user=user,
        image_keys={
            "front": "ocr/tmp/u/front.jpg",
            "expiry": "ocr/tmp/u/expiry.jpg",
        },
    )
    after = timezone.now() + timedelta(hours=24, minutes=1)
    assert job.status == OCRJob.Status.QUEUED
    assert before < job.expires_at < after


@pytest.mark.django_db
def test_candidate_does_not_store_full_recognized_text(user):
    job = OCRJob.objects.create(user=user, image_keys={"front": "front.jpg"})
    candidate = OCRCandidate.objects.create(
        job=job,
        medicine_name="布洛芬缓释胶囊",
        confidence_json={"medicine_name": 0.94},
        raw_line_count=6,
    )
    field_names = {field.name for field in candidate._meta.fields}
    assert "raw_text" not in field_names
    assert candidate.job_id == job.id

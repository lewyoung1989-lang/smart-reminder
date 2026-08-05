import pytest

from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.models import OCRJob
from apps.ocr.services.job_runner import run_job


class FakeStorage:
    def get_bytes(self, key):
        return b"valid-image"


class FakeProvider:
    def recognize(self, image_bytes, *, role):
        text = "布洛芬缓释胶囊" if role == "front" else "有效期至 2028.05"
        line = OCRLine(
            ((0, 0), (1, 0), (1, 1), (0, 1)),
            text,
            0.96,
        )
        return OCRDocument(role, (line,))


@pytest.mark.django_db
def test_run_job_persists_candidates_not_raw_text(user, monkeypatch):
    monkeypatch.setattr(
        "apps.ocr.services.job_runner.prepare_ocr_variants",
        lambda value, role: (value,),
    )
    job = OCRJob.objects.create(
        user=user,
        image_keys={"front": "front", "expiry": "expiry"},
    )

    run_job(job.id, storage=FakeStorage(), provider=FakeProvider())

    job.refresh_from_db()
    assert job.status == OCRJob.Status.SUCCEEDED
    assert job.candidate.medicine_name == "布洛芬缓释胶囊"
    assert str(job.candidate.expiry_date) == "2028-05-31"
    assert job.candidate.raw_line_count == 2


@pytest.mark.django_db
def test_repeated_successful_run_keeps_one_candidate(user, monkeypatch):
    monkeypatch.setattr(
        "apps.ocr.services.job_runner.prepare_ocr_variants",
        lambda value, role: (value,),
    )
    job = OCRJob.objects.create(
        user=user,
        image_keys={"front": "front"},
    )

    run_job(job.id, storage=FakeStorage(), provider=FakeProvider())
    run_job(job.id, storage=FakeStorage(), provider=FakeProvider())

    job.refresh_from_db()
    assert job.attempt_count == 1
    assert job.candidate.raw_line_count == 1


@pytest.mark.django_db
def test_run_job_merges_duplicate_expiry_variant_lines(user, monkeypatch):
    monkeypatch.setattr(
        "apps.ocr.services.job_runner.prepare_ocr_variants",
        lambda value, role: (b"original", b"enhanced")
        if role == "expiry"
        else (b"original",),
    )

    class VariantProvider:
        def recognize(self, image_bytes, *, role):
            text = "阿莫西林胶囊" if role == "front" else "有效期至2028.05"
            score = 0.98 if image_bytes == b"enhanced" else 0.90
            return OCRDocument(
                role,
                (
                    OCRLine(
                        ((0, 0), (100, 0), (100, 10), (0, 10)),
                        text,
                        score,
                    ),
                ),
            )

    job = OCRJob.objects.create(
        user=user,
        image_keys={"front": "front", "expiry": "expiry"},
    )

    run_job(job.id, storage=FakeStorage(), provider=VariantProvider())

    job.refresh_from_db()
    assert job.status == OCRJob.Status.SUCCEEDED
    assert job.candidate.raw_line_count == 2
    assert str(job.candidate.expiry_date) == "2028-05-31"

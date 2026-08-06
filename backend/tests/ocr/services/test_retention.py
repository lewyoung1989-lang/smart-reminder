from datetime import timedelta

import pytest
from django.utils import timezone

from apps.ocr.models import OCRJob
from apps.ocr.services.retention import delete_job_images, purge_expired_images


class FakeStorage:
    def __init__(self, *, fail_on=None):
        self.deleted = []
        self.fail_on = fail_on

    def delete(self, key):
        if key == self.fail_on:
            raise RuntimeError("delete failed")
        self.deleted.append(key)


@pytest.mark.django_db
def test_delete_clears_keys_after_all_objects_are_removed(user):
    job = OCRJob.objects.create(
        user=user,
        image_keys={"front": "a", "expiry": "b"},
    )
    storage = FakeStorage()

    delete_job_images(job.id, storage=storage)

    job.refresh_from_db()
    assert storage.deleted == ["a", "b"]
    assert job.image_keys == {}


@pytest.mark.django_db
def test_delete_failure_keeps_keys_for_retry(user):
    job = OCRJob.objects.create(
        user=user,
        image_keys={"front": "a", "expiry": "b"},
    )
    storage = FakeStorage(fail_on="b")

    with pytest.raises(RuntimeError, match="delete failed"):
        delete_job_images(job.id, storage=storage)

    job.refresh_from_db()
    assert job.image_keys == {"front": "a", "expiry": "b"}


@pytest.mark.django_db
def test_purge_deletes_expired_jobs_with_remaining_images(user):
    expired = OCRJob.objects.create(user=user, image_keys={"front": "a"})
    active = OCRJob.objects.create(user=user, image_keys={"front": "b"})
    OCRJob.objects.filter(id=expired.id).update(
        expires_at=timezone.now() - timedelta(seconds=1)
    )
    storage = FakeStorage()

    assert purge_expired_images(storage=storage) == 1

    expired.refresh_from_db()
    active.refresh_from_db()
    assert storage.deleted == ["a"]
    assert expired.image_keys == {}
    assert active.image_keys == {"front": "b"}


@pytest.mark.django_db
def test_purge_continues_after_one_expired_job_fails(user, caplog):
    failed_key = "secret-object-key.jpg"
    failed = OCRJob.objects.create(user=user, image_keys={"front": failed_key})
    removed = OCRJob.objects.create(user=user, image_keys={"front": "good"})
    OCRJob.objects.filter(id__in=[failed.id, removed.id]).update(
        expires_at=timezone.now() - timedelta(seconds=1)
    )
    storage = FakeStorage(fail_on=failed_key)

    with caplog.at_level("WARNING"):
        assert purge_expired_images(storage=storage) == 1

    failed.refresh_from_db()
    removed.refresh_from_db()
    assert failed.image_keys == {"front": failed_key}
    assert removed.image_keys == {}
    assert str(failed.id) in caplog.text
    assert "error_code=image_delete_failed" in caplog.text
    assert failed_key not in caplog.text

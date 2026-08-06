from datetime import date

import pytest
from django.test import override_settings

from apps.medicines.models import InventoryBatch, MedicineItem
from apps.ocr.models import OCRCandidate, OCRJob


def confirm_payload():
    return {
        "medicine_name": "布洛芬胶囊",
        "specification": "0.3g*20粒",
        "batch_number": "20260108",
        "production_date": "2026-01-08",
        "expiry_date": "2028-05-31",
        "quantity": 2,
    }


@pytest.mark.django_db
def test_confirm_creates_edited_inventory_once(
    api_client,
    user,
    mocker,
    django_capture_on_commit_callbacks,
):
    delay = mocker.patch("apps.ocr.api.views.delete_ocr_job_images.delay")
    job = OCRJob.objects.create(
        user=user,
        status=OCRJob.Status.SUCCEEDED,
        image_keys={"front": "front"},
    )
    OCRCandidate.objects.create(job=job, medicine_name="识别错的名称")
    api_client.force_authenticate(user)

    with django_capture_on_commit_callbacks(execute=True):
        first = api_client.post(
            f"/api/v1/ocr/jobs/{job.id}/confirm",
            confirm_payload(),
            format="json",
        )
    second = api_client.post(
        f"/api/v1/ocr/jobs/{job.id}/confirm",
        confirm_payload(),
        format="json",
    )

    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json()["inventory_batch_id"] == second.json()[
        "inventory_batch_id"
    ]
    medicine = MedicineItem.objects.get()
    batch = InventoryBatch.objects.get()
    assert medicine.name == "布洛芬胶囊"
    assert batch.expiry_date == date(2028, 5, 31)
    assert batch.quantity == 2
    delay.assert_called_once_with(str(job.id))


@pytest.mark.django_db
def test_confirm_rejects_job_before_ocr_succeeds(api_client, user):
    job = OCRJob.objects.create(user=user, image_keys={"front": "front"})
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/ocr/jobs/{job.id}/confirm",
        confirm_payload(),
        format="json",
    )

    assert response.status_code == 409
    assert InventoryBatch.objects.count() == 0


@pytest.mark.django_db
def test_confirm_rejects_expiry_before_production(api_client, user):
    job = OCRJob.objects.create(
        user=user,
        status=OCRJob.Status.SUCCEEDED,
        image_keys={"front": "front"},
    )
    api_client.force_authenticate(user)
    payload = confirm_payload()
    payload["expiry_date"] = "2025-01-01"

    response = api_client.post(
        f"/api/v1/ocr/jobs/{job.id}/confirm",
        payload,
        format="json",
    )

    assert response.status_code == 400
    assert InventoryBatch.objects.count() == 0


@pytest.mark.django_db
def test_confirm_is_scoped_to_owner(
    api_client,
    django_user_model,
    user,
):
    another = django_user_model.objects.create_user(username="other-confirm")
    job = OCRJob.objects.create(
        user=another,
        status=OCRJob.Status.SUCCEEDED,
        image_keys={"front": "front"},
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/ocr/jobs/{job.id}/confirm",
        confirm_payload(),
        format="json",
    )

    assert response.status_code == 404
    assert InventoryBatch.objects.count() == 0


@pytest.mark.django_db
@override_settings(OCR_ENABLED=False)
def test_disabled_ocr_rejects_confirm_without_inventory_or_cleanup(
    api_client, user, mocker
):
    delay = mocker.patch("apps.ocr.api.views.delete_ocr_job_images.delay")
    job = OCRJob.objects.create(
        user=user,
        status=OCRJob.Status.SUCCEEDED,
        image_keys={"front": "front"},
    )
    OCRCandidate.objects.create(job=job, medicine_name="识别名称")
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/ocr/jobs/{job.id}/confirm",
        confirm_payload(),
        format="json",
    )

    assert response.status_code == 503
    assert response.json() == {"code": "ocr_disabled"}
    assert InventoryBatch.objects.count() == 0
    delay.assert_not_called()

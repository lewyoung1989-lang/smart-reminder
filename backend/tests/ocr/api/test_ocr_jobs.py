from dataclasses import dataclass
from datetime import datetime, timezone

import pytest
from django.test import override_settings

from apps.ocr.models import OCRCandidate, OCRJob


@dataclass(frozen=True)
class FakeGrant:
    object_key: str = "ocr/tmp/user/random.jpg"
    upload_url: str = "https://upload.invalid/random.jpg"
    headers: dict[str, str] = None
    expires_at: datetime = datetime(2026, 8, 4, tzinfo=timezone.utc)

    def __post_init__(self):
        object.__setattr__(
            self,
            "headers",
            self.headers or {"Content-Type": "image/jpeg"},
        )


@pytest.mark.django_db
def test_upload_requires_authentication(api_client):
    response = api_client.post(
        "/api/v1/ocr/uploads",
        {
            "kind": "front",
            "content_type": "image/jpeg",
            "byte_length": 100,
        },
        format="json",
    )

    assert response.status_code == 401


@pytest.mark.django_db
@override_settings(OCR_ENABLED=False)
@pytest.mark.parametrize(
    ("path", "payload"),
    (
        (
            "/api/v1/ocr/uploads",
            {
                "kind": "front",
                "content_type": "image/jpeg",
                "byte_length": 100,
            },
        ),
        (
            "/api/v1/ocr/jobs",
            {
                "images": [
                    {
                        "kind": "front",
                        "object_key": "ocr/tmp/anonymous/front.jpg",
                    }
                ]
            },
        ),
    ),
)
def test_disabled_ocr_authenticates_before_returning_service_state(
    api_client, path, payload
):
    response = api_client.post(path, payload, format="json")

    assert response.status_code == 401
    assert response.json() != {"code": "ocr_disabled"}


@pytest.mark.django_db
def test_upload_returns_private_signed_grant(api_client, user, mocker):
    create_upload = mocker.patch(
        "apps.ocr.api.views.create_upload",
        return_value=FakeGrant(),
    )
    mocker.patch(
        "apps.ocr.api.views.get_object_storage",
        return_value=object(),
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/ocr/uploads",
        {
            "kind": "front",
            "content_type": "image/jpeg",
            "byte_length": 100,
        },
        format="json",
    )

    assert response.status_code == 201
    assert response.json()["upload_url"].startswith("https://upload.invalid/")
    create_upload.assert_called_once()


@pytest.mark.django_db
def test_create_job_requires_owned_temporary_keys(
    api_client,
    user,
    mocker,
    django_capture_on_commit_callbacks,
):
    delay = mocker.patch("apps.ocr.api.views.process_ocr_job.delay")
    api_client.force_authenticate(user)

    with django_capture_on_commit_callbacks(execute=True):
        response = api_client.post(
            "/api/v1/ocr/jobs",
            {
                "images": [
                    {
                        "kind": "front",
                        "object_key": f"ocr/tmp/{user.id}/front.jpg",
                    },
                    {
                        "kind": "expiry",
                        "object_key": f"ocr/tmp/{user.id}/expiry.jpg",
                    },
                ]
            },
            format="json",
        )

    assert response.status_code == 201
    assert response.json()["status"] == "queued"
    delay.assert_called_once_with(response.json()["id"])


@pytest.mark.django_db
def test_create_job_rejects_another_users_key(
    api_client,
    django_user_model,
    user,
):
    another = django_user_model.objects.create_user(username="other")
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/ocr/jobs",
        {
            "images": [
                {
                    "kind": "front",
                    "object_key": f"ocr/tmp/{another.id}/front.jpg",
                }
            ]
        },
        format="json",
    )

    assert response.status_code == 400


@pytest.mark.django_db
def test_get_succeeded_job_returns_only_normalized_candidate(
    api_client,
    user,
):
    job = OCRJob.objects.create(
        user=user,
        status=OCRJob.Status.SUCCEEDED,
        image_keys={"front": "private-object-key"},
    )
    OCRCandidate.objects.create(
        job=job,
        medicine_name="布洛芬缓释胶囊",
        confidence_json={"medicine_name": 0.96},
        raw_line_count=1,
    )
    api_client.force_authenticate(user)

    response = api_client.get(f"/api/v1/ocr/jobs/{job.id}")

    assert response.status_code == 200
    assert response.json()["candidate"]["medicine_name"] == "布洛芬缓释胶囊"
    assert "image_keys" not in response.json()
    assert "raw_text" not in response.json()
    assert "private-object-key" not in response.content.decode()


@pytest.mark.django_db
def test_get_job_is_scoped_to_owner(api_client, django_user_model, user):
    another = django_user_model.objects.create_user(username="other-owner")
    job = OCRJob.objects.create(user=another, image_keys={"front": "private"})
    api_client.force_authenticate(user)

    response = api_client.get(f"/api/v1/ocr/jobs/{job.id}")

    assert response.status_code == 404


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("job_status", "expected_key"),
    [
        (OCRJob.Status.QUEUED, None),
        (OCRJob.Status.RUNNING, None),
        (OCRJob.Status.FAILED, "error_code"),
    ],
)
def test_get_job_exposes_only_state_for_unfinished_jobs(
    api_client,
    user,
    job_status,
    expected_key,
):
    job = OCRJob.objects.create(
        user=user,
        status=job_status,
        error_code="ocr_failed" if job_status == OCRJob.Status.FAILED else "",
        image_keys={"front": "private"},
    )
    api_client.force_authenticate(user)

    response = api_client.get(f"/api/v1/ocr/jobs/{job.id}")

    assert response.status_code == 200
    assert response.json()["status"] == job_status
    assert ("error_code" in response.json()) is (expected_key is not None)


@pytest.mark.django_db
@override_settings(OCR_ENABLED=False)
def test_disabled_ocr_rejects_upload_without_creating_grant(
    api_client, user, mocker
):
    create_upload = mocker.patch("apps.ocr.api.views.create_upload")
    storage = mocker.patch("apps.ocr.api.views.get_object_storage")
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/ocr/uploads",
        {
            "kind": "front",
            "content_type": "image/jpeg",
            "byte_length": 100,
        },
        format="json",
    )

    assert response.status_code == 503
    assert response.json() == {"code": "ocr_disabled"}
    create_upload.assert_not_called()
    storage.assert_not_called()


@pytest.mark.django_db
@override_settings(OCR_ENABLED=False)
def test_disabled_ocr_rejects_job_create_without_row_or_queue(
    api_client, user, mocker
):
    delay = mocker.patch("apps.ocr.api.views.process_ocr_job.delay")
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/ocr/jobs",
        {
            "images": [
                {
                    "kind": "front",
                    "object_key": f"ocr/tmp/{user.id}/front.jpg",
                }
            ]
        },
        format="json",
    )

    assert response.status_code == 503
    assert response.json() == {"code": "ocr_disabled"}
    assert OCRJob.objects.count() == 0
    delay.assert_not_called()


@pytest.mark.django_db
@override_settings(OCR_ENABLED=False)
def test_disabled_ocr_rejects_job_query(api_client, user):
    job = OCRJob.objects.create(user=user, image_keys={"front": "private"})
    api_client.force_authenticate(user)

    response = api_client.get(f"/api/v1/ocr/jobs/{job.id}")

    assert response.status_code == 503
    assert response.json() == {"code": "ocr_disabled"}

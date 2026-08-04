# Self-Hosted Medicine OCR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a low-cost medicine-box OCR flow that extracts reviewable medicine and expiry candidates with self-hosted RapidOCR, then creates medicine inventory only after explicit user confirmation.

**Architecture:** The Flutter app captures the medicine front and expiry area separately and uploads compressed images through short-lived signed URLs. Django persists an OCR job and dispatches it to a dedicated Celery `ocr` queue; a CPU-only RapidOCR adapter returns normalized text lines, deterministic rules extract medicine fields, and confirmation atomically creates the medicine and inventory batch. Provider and object-storage protocols keep Alibaba Cloud OCR and local storage replaceable without changing business logic.

**Tech Stack:** Python 3.13, Django 5.2, Django REST Framework 3.16, Celery 5.5, Redis 7, RapidOCR 3.9.2, ONNX Runtime 1.28.0, OpenCV, PostgreSQL 16, private S3-compatible storage (COS/OSS/MinIO), Flutter/Dart, `image_picker`.

---

## Scope, Decisions, And File Map

This plan is one independently testable OCR vertical slice. It includes two-photo capture, signed upload, asynchronous OCR, deterministic candidate extraction, review, confirmation, retention, and deployment. It does not train a model, build a medicine knowledge graph, infer medical advice, or automatically accept OCR output.

Approved decisions:

- Use `RapidOCR(params={"Rec.lang_type": "ch"})` with ONNX Runtime on CPU; no GPU and no model training.
- Keep `OCRProvider` as a protocol. `rapidocr` is the default; Alibaba OCR is only a future configurable fallback.
- Keep the OCR process in a dedicated Celery queue with concurrency `1`; do not import or initialize RapidOCR in the API process.
- Store only normalized candidate fields and confidence values in PostgreSQL. Do not store complete recognized text in database or logs.
- Require the user to review every candidate before creating inventory.
- Delete temporary images after confirmation and purge every expired job image after at most 24 hours.

File ownership:

- `backend/apps/medicines/`: confirmed medicine and inventory-batch data only.
- `backend/apps/ocr/domain/`: provider-neutral OCR and parser types with no Django imports.
- `backend/apps/ocr/providers/`: RapidOCR and object-storage adapters.
- `backend/apps/ocr/services/`: job orchestration, confirmation, image validation, and retention.
- `backend/apps/ocr/api/`: authenticated upload, job, result, and confirmation endpoints.
- `backend/apps/ocr/tasks.py`: Celery execution and cleanup entry points.
- `app/lib/features/medicine_ocr/`: capture, upload, polling, candidate review, and confirmation UI.
- `backend/requirements/ocr.txt` and `backend/Dockerfile.ocr`: OCR-only native/runtime dependencies, excluded from the API image.

Execution note: inspect `git status` before Task 9, preserve any concurrent dependency or notification edits, and add only the `image_picker` dependency to `app/pubspec.yaml`. Do not rewrite `reminder_composer_screen.dart` or files under `app/lib/platform/notifications/` for this feature.

## Deployment And Configuration Checklist

### Recommended Tencent Cloud offer for the family beta

Offer snapshot verified on 2026-08-04 from the supplied Tencent Cloud page. The page states this activity runs through 2026-08-31 23:59:59 and may change; verify the checkout summary before payment.

| Offer | Current activity price | OCR suitability | Decision |
|---|---:|---|---|
| Lighthouse 4 vCPU / 4 GB / 3 Mbps, Shanghai, 1 year | CNY 109; listed regular price CNY 780/year | Best short beta value; enough CPU for one OCR worker and enough RAM for the full Compose stack with tuning | **Recommended first purchase** |
| Lighthouse 2 vCPU / 4 GB / 6 Mbps, Shanghai, 3 years | CNY 528; listed regular total CNY 2,700 | Suitable and longer-lived, but OCR is slower and three-year lock-in is unnecessary before product validation | Alternative when the three-year term is intentional |
| Lighthouse 2 vCPU / 2 GB / 3 Mbps, Shanghai, 1 year | CNY 68 | Memory is too tight for Django, PostgreSQL, Redis, and RapidOCR on one host | Do not use for this stack |
| CVM BF1 2 vCPU / 4 GB / 1 Mbps, Beijing Zone 7, 1 year | CNY 484.06; listed regular price CNY 1,792.80/year | Suitable and more flexible for VPC/cloud-disk architecture, but weaker value for the first beta | Use only when CVM networking/managed-service integration is required |

The activity rules state that promotional Lighthouse configurations cannot be resized and renew at the normal catalog price. Eligibility is limited to qualifying new users/product-new users. Before purchase, verify system-disk capacity is at least 60 GB, included monthly traffic, Linux image availability, refund terms, and whether the account qualifies. Do not buy the `2 vCPU / 2 GB` offer just because it is CNY 68.

For this first deployment, run Nginx, Django API, PostgreSQL, Redis, ordinary Celery worker/Beat, and the concurrency-1 OCR worker on the `4 vCPU / 4 GB` Lighthouse instance. Put medicine images in private COS, cap OCR worker memory at 1.2 GB, configure swap only as an OOM safety net rather than working memory, and move PostgreSQL/Redis to managed services when monitoring shows sustained memory pressure or before public beta.

### Cloud-neutral MVP sizing

| Component | Minimum | Recommended for family beta | Notes |
|---|---:|---:|---|
| Compute host | 2 vCPU / 2 GB | 2 vCPU / 4 GB | Use 4 GB when API and OCR Worker share one host; no GPU instance |
| System/data disk | 40 GB SSD | 60 GB SSD | Leave room for Docker layers, models, logs, and rollbacks; images remain in object storage |
| OCR Worker | 1 process | 1 process, 1 CPU limit | `--concurrency=1 --prefetch-multiplier=1`; target 700 MB reservation and 1.2 GB limit |
| Managed PostgreSQL | smallest supported test tier | 1 vCPU / 2 GB, 20 GB storage | Alibaba RDS or TencentDB; automatic backups and private-network access only |
| Managed Redis | 256 MB test tier | 1 GB standard | Alibaba Tair or TencentDB for Redis; private-network access only |
| Object storage | private Standard bucket | private Standard bucket | Alibaba OSS or Tencent COS; HTTPS, restricted CORS, lifecycle purge after 1 day |
| Public ingress | HTTPS 443 | HTTPS 443 | Only Nginx/API is public; never expose PostgreSQL, Redis, or object-storage credentials |

Cost-down option for the first few testers: keep PostgreSQL and Redis in Docker on a single `4 vCPU / 4 GB` Tencent Lighthouse or `2 vCPU / 4 GB` ECS/CVM, enable daily encrypted backups, and move them to managed PostgreSQL/Redis before public beta. A `2 vCPU / 2 GB` host is acceptable only when the database, Redis, and object storage are external and OCR request volume is low.

### Required environment variables

```dotenv
OCR_PROVIDER=rapidocr
OCR_LANGUAGE=ch
OCR_TEXT_SCORE=0.50
OCR_MAX_IMAGE_BYTES=8388608
OCR_MAX_IMAGE_SIDE=2048
OCR_JOB_RETENTION_HOURS=24
OCR_WORKER_CONCURRENCY=1
OCR_TASK_SOFT_TIME_LIMIT=45
OCR_TASK_TIME_LIMIT=60
OCR_MAX_RETRIES=2
OCR_MODEL_ROOT=/var/lib/smart-reminder/ocr-models
OCR_QUEUE=ocr
OCR_STORAGE_PROVIDER=s3
OCR_UPLOAD_URL_TTL_SECONDS=600
S3_ENDPOINT=https://cos.ap-shanghai.myqcloud.com
S3_BUCKET=smart-reminder-private
S3_REGION=ap-shanghai
S3_ADDRESSING_STYLE=virtual
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
```

Production secrets belong in KMS/role injection, not `.env`, source control, Docker image layers, or the Flutter app. Prefer an ECS RAM role or Tencent Cloud service role over long-lived `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY`.

### Runtime checklist

- [ ] Private OSS/COS bucket created; anonymous read/list disabled; server-side encryption enabled.
- [ ] Object-storage CORS permits only `PUT`, the required `Content-Type`, and the actual app/API origins.
- [ ] Object-storage lifecycle deletes `ocr/tmp/` objects after 1 day as a second safety net.
- [ ] API and `ocr-worker` use separate images; only `ocr-worker` installs RapidOCR, ONNX Runtime, and OpenCV native libraries.
- [ ] OCR model files are warmed during image build or deployment and mounted read-only at `OCR_MODEL_ROOT`; production startup does not download models from the internet.
- [ ] Worker starts with `celery -A config worker -Q ocr --concurrency=1 --prefetch-multiplier=1 --loglevel=INFO`.
- [ ] Worker has a `1 CPU` limit, about `700 MB` reservation, and `1.2 GB` memory limit; alert before sustained OOM/restarts.
- [ ] Celery soft/hard limits are `45/60` seconds and retry count is `2`.
- [ ] Logs include `job_id`, `duration_ms`, `line_count`, provider, and error code only; they exclude image bytes, signed URLs, object keys containing personal data, and complete OCR text.
- [ ] Smoke check loads the model and recognizes a committed synthetic fixture before traffic is enabled.
- [ ] Redis, PostgreSQL, and object-storage administration ports are private; security groups expose only SSH from an administrator IP and HTTPS from the internet.
- [ ] Cloud monitoring alarms cover host memory, worker restarts, OCR queue depth, p95 duration, failure rate, and object deletion failures.

## API Contract

```text
POST /api/v1/ocr/uploads
  request:  {"kind":"front|expiry","content_type":"image/jpeg","byte_length":123456}
  response: {"object_key":"ocr/tmp/<user>/<uuid>.jpg","upload_url":"...","headers":{"Content-Type":"image/jpeg"},"expires_at":"..."}

POST /api/v1/ocr/jobs
  request:  {"images":[{"kind":"front","object_key":"..."},{"kind":"expiry","object_key":"..."}]}
  response: {"id":"<uuid>","status":"queued"}

GET /api/v1/ocr/jobs/<id>
  response while running: {"id":"...","status":"queued|running"}
  response after OCR:      {"id":"...","status":"succeeded","candidate":{...}}

POST /api/v1/ocr/jobs/<id>/confirm
  request:  {"medicine_name":"布洛芬缓释胶囊","specification":"0.3g*20粒","batch_number":"...","production_date":"2026-01-01","expiry_date":"2028-01-01","quantity":1}
  response: {"medicine_id":"<uuid>","inventory_batch_id":"<uuid>","status":"confirmed"}
```

## Task 1: Pin OCR Dependencies And Settings

**Files:**
- Create: `backend/requirements/ocr.txt`
- Modify: `backend/requirements/dev.txt`
- Modify: `backend/config/settings.py`
- Modify: `.env.example`
- Test: `backend/tests/ocr/test_settings.py`

- [ ] **Step 1: Write the failing settings test**

```python
# backend/tests/ocr/test_settings.py
from django.conf import settings


def test_ocr_defaults_are_safe_for_cpu_worker():
    assert settings.OCR_PROVIDER == "rapidocr"
    assert settings.OCR_LANGUAGE == "ch"
    assert settings.OCR_TEXT_SCORE == 0.50
    assert settings.OCR_MAX_IMAGE_BYTES == 8 * 1024 * 1024
    assert settings.OCR_MAX_IMAGE_SIDE == 2048
    assert settings.OCR_JOB_RETENTION_HOURS == 24
    assert settings.OCR_TASK_SOFT_TIME_LIMIT == 45
    assert settings.OCR_TASK_TIME_LIMIT == 60
    assert settings.OCR_MAX_RETRIES == 2
```

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/test_settings.py -q`

Expected: FAIL with `AttributeError: 'Settings' object has no attribute 'OCR_PROVIDER'`.

- [ ] **Step 3: Add the OCR-only dependency file and settings**

```text
# backend/requirements/ocr.txt
-r base.txt
rapidocr==3.9.2
onnxruntime==1.28.0
```

```text
# append to backend/requirements/dev.txt
pytest-mock==3.14.1
```

Do not add `opencv-python-headless`: RapidOCR 3.9.2 directly installs `opencv_python`, and installing both packages can produce conflicting `cv2` files.

```python
# append to backend/config/settings.py
OCR_PROVIDER = os.environ.get("OCR_PROVIDER", "rapidocr")
OCR_LANGUAGE = os.environ.get("OCR_LANGUAGE", "ch")
OCR_TEXT_SCORE = float(os.environ.get("OCR_TEXT_SCORE", "0.50"))
OCR_MAX_IMAGE_BYTES = int(os.environ.get("OCR_MAX_IMAGE_BYTES", str(8 * 1024 * 1024)))
OCR_MAX_IMAGE_SIDE = int(os.environ.get("OCR_MAX_IMAGE_SIDE", "2048"))
OCR_JOB_RETENTION_HOURS = int(os.environ.get("OCR_JOB_RETENTION_HOURS", "24"))
OCR_TASK_SOFT_TIME_LIMIT = int(os.environ.get("OCR_TASK_SOFT_TIME_LIMIT", "45"))
OCR_TASK_TIME_LIMIT = int(os.environ.get("OCR_TASK_TIME_LIMIT", "60"))
OCR_MAX_RETRIES = int(os.environ.get("OCR_MAX_RETRIES", "2"))
OCR_MODEL_ROOT = os.environ.get("OCR_MODEL_ROOT", "")
OCR_QUEUE = os.environ.get("OCR_QUEUE", "ocr")
OCR_STORAGE_PROVIDER = os.environ.get("OCR_STORAGE_PROVIDER", "s3")
OCR_UPLOAD_URL_TTL_SECONDS = int(os.environ.get("OCR_UPLOAD_URL_TTL_SECONDS", "600"))
S3_ENDPOINT = os.environ.get("S3_ENDPOINT", "http://localhost:9000")
S3_BUCKET = os.environ.get("S3_BUCKET", "smart-reminder-private")
S3_REGION = os.environ.get("S3_REGION", "us-east-1")
S3_ADDRESSING_STYLE = os.environ.get("S3_ADDRESSING_STYLE", "auto")
S3_ACCESS_KEY_ID = os.environ.get("S3_ACCESS_KEY_ID", "")
S3_SECRET_ACCESS_KEY = os.environ.get("S3_SECRET_ACCESS_KEY", "")

CELERY_TASK_ROUTES = {"apps.ocr.tasks.*": {"queue": OCR_QUEUE}}
CELERY_TASK_SOFT_TIME_LIMIT = OCR_TASK_SOFT_TIME_LIMIT
CELERY_TASK_TIME_LIMIT = OCR_TASK_TIME_LIMIT
```

Append the environment block from “Required environment variables” to `.env.example`, but set `OCR_STORAGE_PROVIDER=s3`, `OCR_MODEL_ROOT=` and the endpoint to local MinIO for local development. An empty model root makes RapidOCR use its packaged models; production sets the read-only directory containing `det.onnx`, `cls.onnx`, and `rec.onnx`.

- [ ] **Step 4: Run the settings test and dependency compatibility check**

Run: `.venv/bin/pytest backend/tests/ocr/test_settings.py -q`

Expected: `1 passed`.

Run: `.venv/bin/python -m pip install -r backend/requirements/ocr.txt && .venv/bin/python -c "import cv2, onnxruntime, rapidocr; print(onnxruntime.__version__)"`

Expected: command exits `0` and prints `1.28.0`.

- [ ] **Step 5: Commit the dependency boundary**

```bash
git add backend/requirements/ocr.txt backend/requirements/dev.txt backend/config/settings.py backend/tests/ocr/test_settings.py .env.example
git commit -m "build: add self-hosted OCR configuration"
```

## Task 2: Add Medicine Inventory And OCR Job Models

**Files:**
- Create: `backend/apps/medicines/apps.py`
- Create: `backend/apps/medicines/models.py`
- Create: `backend/apps/medicines/migrations/0001_initial.py`
- Create: `backend/apps/ocr/apps.py`
- Create: `backend/apps/ocr/models.py`
- Create: `backend/apps/ocr/migrations/0001_initial.py`
- Modify: `backend/config/settings.py`
- Test: `backend/tests/ocr/test_models.py`

- [ ] **Step 1: Write failing model tests**

```python
# backend/tests/ocr/test_models.py
from datetime import timedelta

import pytest
from django.utils import timezone

from apps.ocr.models import OCRCandidate, OCRJob


@pytest.mark.django_db
def test_job_defaults_to_queued_and_expires_in_24_hours(user):
    before = timezone.now() + timedelta(hours=23, minutes=59)
    job = OCRJob.objects.create(
        user=user,
        image_keys={"front": "ocr/tmp/u/front.jpg", "expiry": "ocr/tmp/u/expiry.jpg"},
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
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/test_models.py -q`

Expected: FAIL with `ModuleNotFoundError: No module named 'apps.ocr'`.

- [ ] **Step 3: Implement focused models**

```python
# backend/apps/medicines/models.py
import uuid

from django.conf import settings
from django.db import models


class MedicineItem(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    name = models.CharField(max_length=200)
    specification = models.CharField(max_length=120, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["owner", "name", "specification"],
                name="unique_owner_medicine_specification",
            )
        ]


class InventoryBatch(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    medicine = models.ForeignKey(MedicineItem, on_delete=models.CASCADE, related_name="batches")
    batch_number = models.CharField(max_length=100, blank=True)
    production_date = models.DateField(null=True, blank=True)
    expiry_date = models.DateField(null=True, blank=True)
    quantity = models.PositiveIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
```

```python
# backend/apps/ocr/models.py
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
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.QUEUED)
    image_keys = models.JSONField()
    provider = models.CharField(max_length=32, default="rapidocr")
    attempt_count = models.PositiveSmallIntegerField(default=0)
    error_code = models.CharField(max_length=64, blank=True)
    confirmed_batch = models.OneToOneField(
        "medicines.InventoryBatch", null=True, blank=True, on_delete=models.SET_NULL
    )
    expires_at = models.DateTimeField(default=default_expiry)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class OCRCandidate(models.Model):
    job = models.OneToOneField(OCRJob, on_delete=models.CASCADE, related_name="candidate")
    medicine_name = models.CharField(max_length=200, blank=True)
    specification = models.CharField(max_length=120, blank=True)
    batch_number = models.CharField(max_length=100, blank=True)
    production_date = models.DateField(null=True, blank=True)
    expiry_date = models.DateField(null=True, blank=True)
    confidence_json = models.JSONField(default=dict)
    raw_line_count = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
```

```python
# backend/apps/medicines/apps.py
from django.apps import AppConfig


class MedicinesConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.medicines"
```

```python
# backend/apps/ocr/apps.py
from django.apps import AppConfig


class OCRConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.ocr"
```

Add both app configs to `INSTALLED_APPS`:

```python
"apps.medicines.apps.MedicinesConfig",
"apps.ocr.apps.OCRConfig",
```

Generate migrations rather than handwriting migration operations.

- [ ] **Step 4: Generate migrations and run the tests**

Run: `.venv/bin/python backend/manage.py makemigrations medicines ocr`

Expected: creates `medicines/migrations/0001_initial.py` and `ocr/migrations/0001_initial.py`.

Run: `.venv/bin/pytest backend/tests/ocr/test_models.py -q`

Expected: `2 passed`.

- [ ] **Step 5: Commit the data model**

```bash
git add backend/apps/medicines backend/apps/ocr backend/config/settings.py backend/tests/ocr/test_models.py
git commit -m "feat: add medicine OCR job models"
```

## Task 3: Define The Provider Contract And RapidOCR Adapter

**Files:**
- Create: `backend/apps/ocr/domain/types.py`
- Create: `backend/apps/ocr/providers/base.py`
- Create: `backend/apps/ocr/providers/rapidocr.py`
- Create: `backend/apps/ocr/providers/factory.py`
- Test: `backend/tests/ocr/providers/test_rapidocr.py`

- [ ] **Step 1: Write failing adapter tests with a fake engine**

```python
# backend/tests/ocr/providers/test_rapidocr.py
from types import SimpleNamespace

from apps.ocr.providers.rapidocr import RapidOCRProvider


class FakeEngine:
    def __call__(self, image_bytes):
        assert image_bytes == b"jpeg"
        return SimpleNamespace(
            boxes=[[[0, 0], [20, 0], [20, 10], [0, 10]], [[0, 12], [20, 12], [20, 22], [0, 22]]],
            txts=["布洛芬缓释胶囊", "低置信度"],
            scores=[0.96, 0.30],
        )


def test_adapter_normalizes_and_filters_lines():
    provider = RapidOCRProvider(engine=FakeEngine(), minimum_score=0.50)
    document = provider.recognize(b"jpeg", role="front")
    assert document.role == "front"
    assert [line.text for line in document.lines] == ["布洛芬缓释胶囊"]
    assert document.lines[0].score == 0.96
```

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/providers/test_rapidocr.py -q`

Expected: FAIL because `apps.ocr.providers.rapidocr` does not exist.

- [ ] **Step 3: Implement provider-neutral immutable types and adapter**

```python
# backend/apps/ocr/domain/types.py
from dataclasses import dataclass
from datetime import date
from typing import Literal


Point = tuple[float, float]


@dataclass(frozen=True)
class OCRLine:
    box: tuple[Point, Point, Point, Point]
    text: str
    score: float


@dataclass(frozen=True)
class OCRDocument:
    role: Literal["front", "expiry"]
    lines: tuple[OCRLine, ...]


@dataclass(frozen=True)
class MedicineCandidates:
    medicine_name: str = ""
    specification: str = ""
    batch_number: str = ""
    production_date: date | None = None
    expiry_date: date | None = None
    confidence: dict[str, float] | None = None
```

```python
# backend/apps/ocr/providers/base.py
from typing import Protocol

from apps.ocr.domain.types import OCRDocument


class OCRProvider(Protocol):
    def recognize(self, image_bytes: bytes, *, role: str) -> OCRDocument: ...
```

```python
# backend/apps/ocr/providers/rapidocr.py
from functools import lru_cache

from django.conf import settings
from rapidocr import RapidOCR

from apps.ocr.domain.types import OCRDocument, OCRLine


@lru_cache(maxsize=1)
def get_engine():
    params = {"Rec.lang_type": settings.OCR_LANGUAGE}
    root = settings.OCR_MODEL_ROOT
    if root:
        params.update({
            "Det.model_path": f"{root}/det.onnx",
            "Cls.model_path": f"{root}/cls.onnx",
            "Rec.model_path": f"{root}/rec.onnx",
        })
    return RapidOCR(params=params)


class RapidOCRProvider:
    def __init__(self, *, engine=None, minimum_score=None):
        self._engine = engine
        self._minimum_score = settings.OCR_TEXT_SCORE if minimum_score is None else minimum_score

    def recognize(self, image_bytes: bytes, *, role: str) -> OCRDocument:
        result = (self._engine or get_engine())(image_bytes)
        lines = []
        if result is not None and result.txts is not None:
            for box, value, score in zip(result.boxes, result.txts, result.scores, strict=True):
                if float(score) >= self._minimum_score:
                    points = tuple(tuple(float(v) for v in point) for point in box)
                    lines.append(OCRLine(box=points, text=value.strip(), score=float(score)))
        return OCRDocument(role=role, lines=tuple(lines))
```

```python
# backend/apps/ocr/providers/factory.py
from django.conf import settings

from .rapidocr import RapidOCRProvider


def get_ocr_provider():
    if settings.OCR_PROVIDER == "rapidocr":
        return RapidOCRProvider()
    raise ValueError(f"Unsupported OCR provider: {settings.OCR_PROVIDER}")
```

- [ ] **Step 4: Run the adapter tests**

Run: `.venv/bin/pytest backend/tests/ocr/providers/test_rapidocr.py -q`

Expected: `1 passed` without loading the real model.

- [ ] **Step 5: Commit the adapter**

```bash
git add backend/apps/ocr/domain backend/apps/ocr/providers backend/tests/ocr/providers
git commit -m "feat: add RapidOCR provider adapter"
```

## Task 4: Extract Medicine Fields Without Confusing Dates

**Files:**
- Create: `backend/apps/ocr/domain/medicine_parser.py`
- Test: `backend/tests/ocr/domain/test_medicine_parser.py`

- [ ] **Step 1: Write representative failing parser tests**

```python
# backend/tests/ocr/domain/test_medicine_parser.py
from datetime import date

import pytest

from apps.ocr.domain.medicine_parser import extract_candidates
from apps.ocr.domain.types import OCRDocument, OCRLine


def line(text, score=0.95):
    return OCRLine(box=((0, 0), (1, 0), (1, 1), (0, 1)), text=text, score=score)


def test_extracts_front_and_expiry_fields():
    result = extract_candidates((
        OCRDocument("front", (line("布洛芬缓释胶囊"), line("规格 0.3g*20粒"))),
        OCRDocument("expiry", (line("批号 20260108"), line("有效期至 2028.05"))),
    ))
    assert result.medicine_name == "布洛芬缓释胶囊"
    assert result.specification == "0.3g*20粒"
    assert result.batch_number == "20260108"
    assert result.expiry_date == date(2028, 5, 31)


def test_keeps_production_date_separate_from_expiry_date():
    result = extract_candidates((OCRDocument("expiry", (
        line("生产日期 2026/01/08"),
        line("EXP 05/28"),
    )),))
    assert result.production_date == date(2026, 1, 8)
    assert result.expiry_date == date(2028, 5, 31)


def test_unlabelled_date_is_not_promoted_to_expiry():
    result = extract_candidates((OCRDocument("expiry", (line("2026.01.08"),)),))
    assert result.production_date is None
    assert result.expiry_date is None
```

- [ ] **Step 2: Run the parser tests and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/domain/test_medicine_parser.py -q`

Expected: FAIL because `medicine_parser` does not exist.

- [ ] **Step 3: Implement label-aware extraction**

```python
# backend/apps/ocr/domain/medicine_parser.py
import calendar
import re
from datetime import date

from .types import MedicineCandidates, OCRDocument


EXPIRY_LABEL = re.compile(r"有效期(?:至)?|失效期|EXP", re.IGNORECASE)
PRODUCTION_LABEL = re.compile(r"生产日期|生产日|MFG", re.IGNORECASE)
BATCH = re.compile(r"(?:批号|产品批号|LOT)\s*[:：]?\s*([A-Z0-9-]{4,30})", re.IGNORECASE)
SPEC = re.compile(r"(?:规格\s*[:：]?\s*)?((?:\d+(?:\.\d+)?)(?:mg|g|ml|毫克|克|毫升)(?:[*/xX×]\d+(?:片|粒|袋|支|瓶))?)", re.IGNORECASE)
DATE_YMD = re.compile(r"(20\d{2})[年./-](\d{1,2})(?:[月./-](\d{1,2})日?)?")
DATE_MY = re.compile(r"(?<!\d)(\d{1,2})[./-](\d{2})(?!\d)")
DOSAGE_FORM = re.compile(r"片|胶囊|颗粒|口服液|滴丸|喷雾|软膏|乳膏|糖浆")


def _labelled_date(text: str, label, *, allow_month_year: bool) -> date | None:
    match = label.search(text)
    if not match:
        return None
    value = text[match.end():]
    ymd = DATE_YMD.search(value)
    if ymd:
        year, month = int(ymd.group(1)), int(ymd.group(2))
        day = int(ymd.group(3)) if ymd.group(3) else calendar.monthrange(year, month)[1]
        return date(year, month, day)
    if allow_month_year:
        my = DATE_MY.search(value)
        if my:
            month, year = int(my.group(1)), 2000 + int(my.group(2))
            return date(year, month, calendar.monthrange(year, month)[1])
    return None


def extract_candidates(documents: tuple[OCRDocument, ...]) -> MedicineCandidates:
    values = {"medicine_name": "", "specification": "", "batch_number": ""}
    confidence = {}
    production_date = None
    expiry_date = None
    for document in documents:
        for line in document.lines:
            text = re.sub(r"\s+", "", line.text)
            if document.role == "front" and not values["medicine_name"] and DOSAGE_FORM.search(text):
                if not EXPIRY_LABEL.search(text) and not PRODUCTION_LABEL.search(text):
                    values["medicine_name"] = text
                    confidence["medicine_name"] = line.score
            spec = SPEC.search(text)
            if spec and not values["specification"]:
                values["specification"] = spec.group(1)
                confidence["specification"] = line.score
            batch = BATCH.search(text)
            if batch and not values["batch_number"]:
                values["batch_number"] = batch.group(1)
                confidence["batch_number"] = line.score
            if production_date is None:
                production_date = _labelled_date(text, PRODUCTION_LABEL, allow_month_year=False)
                if production_date:
                    confidence["production_date"] = line.score
            if expiry_date is None:
                expiry_date = _labelled_date(text, EXPIRY_LABEL, allow_month_year=True)
                if expiry_date:
                    confidence["expiry_date"] = line.score
    return MedicineCandidates(
        **values,
        production_date=production_date,
        expiry_date=expiry_date,
        confidence=confidence,
    )
```

- [ ] **Step 4: Run parser tests and add a regression fixture for every supported date form**

Run: `.venv/bin/pytest backend/tests/ocr/domain/test_medicine_parser.py -q`

Expected: `3 passed`.

Add this exact parametrized regression test:

```python
@pytest.mark.parametrize(("text", "expected"), [
    ("有效期 2028/05/31", date(2028, 5, 31)),
    ("失效期2028年5月", date(2028, 5, 31)),
    ("EXP 2028.05", date(2028, 5, 31)),
    ("EXP 05/28", date(2028, 5, 31)),
])
def test_supported_expiry_formats(text, expected):
    result = extract_candidates((OCRDocument("expiry", (line(text),)),))
    assert result.expiry_date == expected
```

- [ ] **Step 5: Commit deterministic extraction**

```bash
git add backend/apps/ocr/domain/medicine_parser.py backend/tests/ocr/domain/test_medicine_parser.py
git commit -m "feat: extract medicine OCR candidates"
```

## Task 5: Add Private Signed Upload Storage

**Files:**
- Modify: `backend/requirements/base.txt`
- Create: `backend/apps/ocr/providers/storage.py`
- Create: `backend/apps/ocr/services/uploads.py`
- Test: `backend/tests/ocr/services/test_uploads.py`

- [ ] **Step 1: Write failing upload-policy tests**

```python
# backend/tests/ocr/services/test_uploads.py
import pytest

from apps.ocr.services.uploads import create_upload


class FakeStorage:
    def presign_put(self, *, key, content_type, expires_in):
        return {"url": f"https://upload.invalid/{key}", "headers": {"Content-Type": content_type}}


def test_upload_key_is_random_and_scoped_to_user(user):
    result = create_upload(
        user=user,
        kind="front",
        content_type="image/jpeg",
        byte_length=100_000,
        storage=FakeStorage(),
    )
    assert result.object_key.startswith(f"ocr/tmp/{user.id}/")
    assert result.object_key.endswith(".jpg")
    assert result.upload_url.startswith("https://upload.invalid/")


def test_rejects_oversized_image(settings, user):
    settings.OCR_MAX_IMAGE_BYTES = 10
    with pytest.raises(ValueError, match="image_too_large"):
        create_upload(user=user, kind="front", content_type="image/jpeg", byte_length=11, storage=FakeStorage())
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/services/test_uploads.py -q`

Expected: FAIL because the upload service does not exist.

- [ ] **Step 3: Implement the S3-compatible storage adapter and upload policy**

Add `boto3==1.40.3` to `backend/requirements/base.txt`. Use `boto3.client("s3", endpoint_url=settings.S3_ENDPOINT, region_name=settings.S3_REGION)` so the same adapter supports Tencent COS, Alibaba OSS, and local MinIO through their S3-compatible endpoints.

```python
# backend/apps/ocr/providers/storage.py
from typing import Protocol

import boto3
from botocore.config import Config
from django.conf import settings


class ObjectStorage(Protocol):
    def presign_put(self, *, key: str, content_type: str, expires_in: int) -> dict: ...
    def get_bytes(self, key: str) -> bytes: ...
    def delete(self, key: str) -> None: ...


class S3ObjectStorage:
    def __init__(self):
        self._bucket = settings.S3_BUCKET
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT,
            region_name=settings.S3_REGION,
            aws_access_key_id=settings.S3_ACCESS_KEY_ID or None,
            aws_secret_access_key=settings.S3_SECRET_ACCESS_KEY or None,
            config=Config(s3={"addressing_style": settings.S3_ADDRESSING_STYLE}),
        )

    def presign_put(self, *, key, content_type, expires_in):
        url = self._client.generate_presigned_url(
            "put_object",
            Params={"Bucket": self._bucket, "Key": key, "ContentType": content_type},
            ExpiresIn=expires_in,
        )
        return {"url": url, "headers": {"Content-Type": content_type}}

    def get_bytes(self, key):
        return self._client.get_object(Bucket=self._bucket, Key=key)["Body"].read()

    def delete(self, key):
        self._client.delete_object(Bucket=self._bucket, Key=key)


def get_object_storage():
    if settings.OCR_STORAGE_PROVIDER in {"s3", "oss"}:
        return S3ObjectStorage()
    raise ValueError(f"Unsupported OCR storage provider: {settings.OCR_STORAGE_PROVIDER}")
```

```python
# backend/apps/ocr/services/uploads.py
from dataclasses import dataclass
from datetime import timedelta
import uuid

from django.conf import settings
from django.utils import timezone


@dataclass(frozen=True)
class UploadGrant:
    object_key: str
    upload_url: str
    headers: dict[str, str]
    expires_at: object


def create_upload(*, user, kind, content_type, byte_length, storage):
    if kind not in {"front", "expiry"}:
        raise ValueError("invalid_image_kind")
    if content_type not in {"image/jpeg", "image/png"}:
        raise ValueError("unsupported_image_type")
    if byte_length > settings.OCR_MAX_IMAGE_BYTES:
        raise ValueError("image_too_large")
    suffix = ".jpg" if content_type == "image/jpeg" else ".png"
    key = f"ocr/tmp/{user.id}/{uuid.uuid4()}{suffix}"
    signed = storage.presign_put(key=key, content_type=content_type, expires_in=settings.OCR_UPLOAD_URL_TTL_SECONDS)
    return UploadGrant(
        object_key=key,
        upload_url=signed["url"],
        headers=signed["headers"],
        expires_at=timezone.now() + timedelta(seconds=settings.OCR_UPLOAD_URL_TTL_SECONDS),
    )
```

The same `S3ObjectStorage` supports local MinIO, Tencent COS, and Alibaba OSS; only endpoint, region, addressing settings, and credentials differ. Add a provider integration test against local MinIO before enabling either cloud endpoint.

- [ ] **Step 4: Run upload tests**

Run: `.venv/bin/pytest backend/tests/ocr/services/test_uploads.py -q`

Expected: `2 passed`.

- [ ] **Step 5: Commit private upload support**

```bash
git add backend/requirements/base.txt backend/config/settings.py backend/apps/ocr/providers/storage.py backend/apps/ocr/services/uploads.py backend/tests/ocr/services/test_uploads.py
git commit -m "feat: add signed medicine image uploads"
```

## Task 6: Process OCR Jobs Safely In Celery

**Files:**
- Create: `backend/apps/ocr/services/image_validation.py`
- Create: `backend/apps/ocr/services/job_runner.py`
- Create: `backend/apps/ocr/tasks.py`
- Test: `backend/tests/ocr/services/test_job_runner.py`
- Test: `backend/tests/ocr/test_tasks.py`
- Create: `backend/tests/ocr/fixtures/medicine_front.jpg`
- Create: `backend/tests/ocr/fixtures/medicine_expiry.jpg`

- [ ] **Step 1: Create synthetic fixture images and failing job-runner tests**

Generate two small synthetic fixtures containing clearly printed text only; do not commit real prescriptions, patient data, addresses, or barcodes.

```python
# backend/tests/ocr/services/test_job_runner.py
import pytest

from apps.ocr.models import OCRJob
from apps.ocr.services.job_runner import run_job
from apps.ocr.domain.types import OCRDocument, OCRLine


class FakeStorage:
    def get_bytes(self, key):
        return b"valid-image"


class FakeProvider:
    def recognize(self, image_bytes, *, role):
        text = "布洛芬缓释胶囊" if role == "front" else "有效期至 2028.05"
        line = OCRLine(((0, 0), (1, 0), (1, 1), (0, 1)), text, 0.96)
        return OCRDocument(role, (line,))


@pytest.mark.django_db
def test_run_job_persists_candidates_not_raw_text(user, monkeypatch):
    monkeypatch.setattr("apps.ocr.services.job_runner.validate_and_resize", lambda value: value)
    job = OCRJob.objects.create(user=user, image_keys={"front": "front", "expiry": "expiry"})
    run_job(job.id, storage=FakeStorage(), provider=FakeProvider())
    job.refresh_from_db()
    assert job.status == OCRJob.Status.SUCCEEDED
    assert job.candidate.medicine_name == "布洛芬缓释胶囊"
    assert str(job.candidate.expiry_date) == "2028-05-31"
    assert job.candidate.raw_line_count == 2
```

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/services/test_job_runner.py -q`

Expected: FAIL because `job_runner` does not exist.

- [ ] **Step 3: Implement image validation and idempotent job execution**

Implement byte limits, OpenCV decoding, and longest-edge resizing without including input bytes in errors:

```python
# backend/apps/ocr/services/image_validation.py
import cv2
import numpy as np
from django.conf import settings


class ImageValidationError(ValueError):
    pass


def validate_and_resize(value: bytes) -> bytes:
    if not value or len(value) > settings.OCR_MAX_IMAGE_BYTES:
        raise ImageValidationError("image_too_large" if value else "invalid_image")
    image = cv2.imdecode(np.frombuffer(value, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ImageValidationError("image_decode_failed")
    height, width = image.shape[:2]
    longest = max(height, width)
    if longest > settings.OCR_MAX_IMAGE_SIDE:
        scale = settings.OCR_MAX_IMAGE_SIDE / longest
        image = cv2.resize(image, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_AREA)
    ok, encoded = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 90])
    if not ok:
        raise ImageValidationError("image_encode_failed")
    return encoded.tobytes()
```

```python
# backend/apps/ocr/services/job_runner.py
from django.db import transaction

from apps.ocr.domain.medicine_parser import extract_candidates
from apps.ocr.models import OCRCandidate, OCRJob
from .image_validation import validate_and_resize


def run_job(job_id, *, storage, provider):
    with transaction.atomic():
        job = OCRJob.objects.select_for_update().get(id=job_id)
        if job.status in {OCRJob.Status.SUCCEEDED, OCRJob.Status.CONFIRMED}:
            return job
        job.status = OCRJob.Status.RUNNING
        job.attempt_count += 1
        job.error_code = ""
        job.save(update_fields=["status", "attempt_count", "error_code", "updated_at"])

    documents = []
    for role in ("front", "expiry"):
        key = job.image_keys.get(role)
        if key:
            image = validate_and_resize(storage.get_bytes(key))
            documents.append(provider.recognize(image, role=role))
    candidates = extract_candidates(tuple(documents))
    line_count = sum(len(document.lines) for document in documents)

    with transaction.atomic():
        job = OCRJob.objects.select_for_update().get(id=job_id)
        OCRCandidate.objects.update_or_create(
            job=job,
            defaults={
                "medicine_name": candidates.medicine_name,
                "specification": candidates.specification,
                "batch_number": candidates.batch_number,
                "production_date": candidates.production_date,
                "expiry_date": candidates.expiry_date,
                "confidence_json": candidates.confidence or {},
                "raw_line_count": line_count,
            },
        )
        job.status = OCRJob.Status.SUCCEEDED
        job.save(update_fields=["status", "updated_at"])
    return job
```

- [ ] **Step 4: Add Celery retry and terminal failure behavior**

```python
# backend/apps/ocr/tasks.py
import logging
import time

from celery import shared_task
from django.conf import settings

from apps.ocr.models import OCRJob
from apps.ocr.providers.factory import get_ocr_provider
from apps.ocr.providers.storage import get_object_storage
from apps.ocr.services.job_runner import run_job


logger = logging.getLogger(__name__)


@shared_task(bind=True, acks_late=True)
def process_ocr_job(self, job_id):
    started = time.monotonic()
    try:
        job = run_job(job_id, storage=get_object_storage(), provider=get_ocr_provider())
        line_count = job.candidate.raw_line_count if hasattr(job, "candidate") else 0
        logger.info("ocr_complete", extra={"job_id": str(job_id), "duration_ms": int((time.monotonic() - started) * 1000), "line_count": line_count, "provider": job.provider})
    except Exception as exc:
        job = OCRJob.objects.get(id=job_id)
        if self.request.retries < settings.OCR_MAX_RETRIES:
            job.status = OCRJob.Status.QUEUED
            job.error_code = "ocr_retryable_failure"
            job.save(update_fields=["status", "error_code", "updated_at"])
            raise self.retry(exc=exc, countdown=2 ** self.request.retries, max_retries=settings.OCR_MAX_RETRIES)
        job.status = OCRJob.Status.FAILED
        job.error_code = "ocr_failed"
        job.save(update_fields=["status", "error_code", "updated_at"])
        logger.warning("ocr_failed", extra={"job_id": str(job_id), "error_code": job.error_code})
```

Test `process_ocr_job.run()` with patched factories. Verify one success, retry state, terminal failed state, and a repeated successful invocation creating only one `OCRCandidate`.

- [ ] **Step 5: Run service and task tests**

Run: `.venv/bin/pytest backend/tests/ocr/services/test_job_runner.py backend/tests/ocr/test_tasks.py -q`

Expected: all tests pass and no real RapidOCR model is loaded.

- [ ] **Step 6: Commit worker processing**

```bash
git add backend/apps/ocr/services backend/apps/ocr/tasks.py backend/tests/ocr
git commit -m "feat: process medicine OCR jobs asynchronously"
```

## Task 7: Expose Upload, Job, Result, And Confirmation APIs

**Files:**
- Create: `backend/apps/ocr/api/serializers.py`
- Create: `backend/apps/ocr/api/views.py`
- Create: `backend/apps/ocr/api/urls.py`
- Create: `backend/apps/ocr/services/confirmation.py`
- Modify: `backend/config/urls.py`
- Test: `backend/tests/ocr/api/test_ocr_jobs.py`
- Test: `backend/tests/ocr/api/test_ocr_confirmation.py`

- [ ] **Step 1: Write failing authenticated job API tests**

```python
# backend/tests/ocr/api/test_ocr_jobs.py
import pytest

from apps.ocr.models import OCRCandidate, OCRJob


@pytest.mark.django_db
def test_create_job_requires_owned_temporary_keys(api_client, user, mocker):
    delay = mocker.patch("apps.ocr.api.views.process_ocr_job.delay")
    api_client.force_authenticate(user)
    response = api_client.post("/api/v1/ocr/jobs", {"images": [
        {"kind": "front", "object_key": f"ocr/tmp/{user.id}/front.jpg"},
        {"kind": "expiry", "object_key": f"ocr/tmp/{user.id}/expiry.jpg"},
    ]}, format="json")
    assert response.status_code == 201
    assert response.json()["status"] == "queued"
    delay.assert_called_once_with(response.json()["id"])


@pytest.mark.django_db
def test_get_succeeded_job_returns_only_normalized_candidate(api_client, user):
    job = OCRJob.objects.create(user=user, status="succeeded", image_keys={"front": "x"})
    OCRCandidate.objects.create(job=job, medicine_name="布洛芬缓释胶囊", confidence_json={"medicine_name": 0.96}, raw_line_count=1)
    api_client.force_authenticate(user)
    response = api_client.get(f"/api/v1/ocr/jobs/{job.id}")
    assert response.status_code == 200
    assert response.json()["candidate"]["medicine_name"] == "布洛芬缓释胶囊"
    assert "raw_text" not in response.json()
```

- [ ] **Step 2: Run API tests and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/api/test_ocr_jobs.py -q`

Expected: FAIL because the OCR URLs and views do not exist.

- [ ] **Step 3: Implement strict serializers and owner-scoped views**

```python
# backend/apps/ocr/api/serializers.py
from rest_framework import serializers


class UploadRequestSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=["front", "expiry"])
    content_type = serializers.ChoiceField(choices=["image/jpeg", "image/png"])
    byte_length = serializers.IntegerField(min_value=1)


class JobImageSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=["front", "expiry"])
    object_key = serializers.CharField(max_length=300)


class CreateJobSerializer(serializers.Serializer):
    images = JobImageSerializer(many=True, min_length=1, max_length=2)

    def validate_images(self, value):
        kinds = [image["kind"] for image in value]
        if len(set(kinds)) != len(kinds) or "front" not in kinds:
            raise serializers.ValidationError("正面图片必填，图片类型不能重复")
        user_prefix = f"ocr/tmp/{self.context['request'].user.id}/"
        if any(not image["object_key"].startswith(user_prefix) for image in value):
            raise serializers.ValidationError("图片不属于当前用户")
        return value


class ConfirmCandidateSerializer(serializers.Serializer):
    medicine_name = serializers.CharField(max_length=200)
    specification = serializers.CharField(max_length=120, allow_blank=True, required=False, default="")
    batch_number = serializers.CharField(max_length=100, allow_blank=True, required=False, default="")
    production_date = serializers.DateField(required=False, allow_null=True)
    expiry_date = serializers.DateField(required=False, allow_null=True)
    quantity = serializers.IntegerField(min_value=1, max_value=999, default=1)

    def validate(self, attrs):
        if attrs.get("production_date") and attrs.get("expiry_date") and attrs["production_date"] > attrs["expiry_date"]:
            raise serializers.ValidationError({"expiry_date": "有效期不能早于生产日期"})
        return attrs
```

Implement owner-scoped views that never return `image_keys`:

```python
# backend/apps/ocr/api/views.py
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.ocr.models import OCRJob
from apps.ocr.providers.storage import get_object_storage
from apps.ocr.services.confirmation import confirm_job
from apps.ocr.services.uploads import create_upload
from apps.ocr.tasks import delete_ocr_job_images, process_ocr_job
from .serializers import ConfirmCandidateSerializer, CreateJobSerializer, UploadRequestSerializer


def _candidate_payload(job):
    if not hasattr(job, "candidate"):
        return None
    value = job.candidate
    return {
        "medicine_name": value.medicine_name,
        "specification": value.specification,
        "batch_number": value.batch_number,
        "production_date": value.production_date.isoformat() if value.production_date else None,
        "expiry_date": value.expiry_date.isoformat() if value.expiry_date else None,
        "confidence": value.confidence_json,
    }


class UploadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = UploadRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            grant = create_upload(user=request.user, storage=get_object_storage(), **serializer.validated_data)
        except ValueError as exc:
            return Response({"code": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({
            "object_key": grant.object_key,
            "upload_url": grant.upload_url,
            "headers": grant.headers,
            "expires_at": grant.expires_at.isoformat(),
        }, status=status.HTTP_201_CREATED)


class JobListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateJobSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        image_keys = {value["kind"]: value["object_key"] for value in serializer.validated_data["images"]}
        with transaction.atomic():
            job = OCRJob.objects.create(user=request.user, image_keys=image_keys)
            transaction.on_commit(lambda: process_ocr_job.delay(str(job.id)))
        return Response({"id": str(job.id), "status": job.status}, status=status.HTTP_201_CREATED)


class JobDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, job_id):
        job = get_object_or_404(OCRJob.objects.select_related("candidate"), id=job_id, user=request.user)
        payload = {"id": str(job.id), "status": job.status}
        if job.status == OCRJob.Status.SUCCEEDED:
            payload["candidate"] = _candidate_payload(job)
        if job.status == OCRJob.Status.FAILED:
            payload["error_code"] = job.error_code
        return Response(payload)


class JobConfirmView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, job_id):
        serializer = ConfirmCandidateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            batch, created = confirm_job(job_id=job_id, user=request.user, fields=serializer.validated_data)
        except OCRJob.DoesNotExist:
            return Response({"detail": "未找到该 OCR 任务"}, status=status.HTTP_404_NOT_FOUND)
        except ValueError as exc:
            return Response({"code": str(exc)}, status=status.HTTP_409_CONFLICT)
        if created:
            transaction.on_commit(lambda: delete_ocr_job_images.delay(str(job_id)))
        return Response({
            "medicine_id": str(batch.medicine_id),
            "inventory_batch_id": str(batch.id),
            "status": "confirmed",
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
```

```python
# backend/apps/ocr/api/urls.py
from django.urls import path

from .views import JobConfirmView, JobDetailView, JobListCreateView, UploadView


urlpatterns = [
    path("uploads", UploadView.as_view(), name="ocr-upload"),
    path("jobs", JobListCreateView.as_view(), name="ocr-job-list"),
    path("jobs/<uuid:job_id>", JobDetailView.as_view(), name="ocr-job-detail"),
    path("jobs/<uuid:job_id>/confirm", JobConfirmView.as_view(), name="ocr-job-confirm"),
]
```

Add `path("api/v1/ocr/", include("apps.ocr.api.urls"))` to `backend/config/urls.py`.

- [ ] **Step 4: Implement idempotent confirmation**

```python
# backend/apps/ocr/services/confirmation.py
from django.db import transaction

from apps.medicines.models import InventoryBatch, MedicineItem
from apps.ocr.models import OCRJob


@transaction.atomic
def confirm_job(*, job_id, user, fields):
    job = OCRJob.objects.select_for_update().get(id=job_id, user=user)
    if job.confirmed_batch_id:
        return job.confirmed_batch, False
    if job.status != OCRJob.Status.SUCCEEDED:
        raise ValueError("ocr_job_not_ready")
    medicine, _ = MedicineItem.objects.get_or_create(
        owner=user,
        name=fields["medicine_name"].strip(),
        specification=fields.get("specification", "").strip(),
    )
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        batch_number=fields.get("batch_number", "").strip(),
        production_date=fields.get("production_date"),
        expiry_date=fields.get("expiry_date"),
        quantity=fields.get("quantity", 1),
    )
    job.confirmed_batch = batch
    job.status = OCRJob.Status.CONFIRMED
    job.save(update_fields=["confirmed_batch", "status", "updated_at"])
    return batch, True
```

The confirmation view returns `201` on the first call and `200` on retries, with the same `medicine_id` and `inventory_batch_id`. It dispatches image deletion after the database transaction commits.

- [ ] **Step 5: Run API and confirmation tests**

Run: `.venv/bin/pytest backend/tests/ocr/api -q`

Expected: tests cover authentication, user isolation, invalid key ownership, pending/failed/succeeded responses, validation, and idempotent confirmation; all pass.

- [ ] **Step 6: Commit the API vertical slice**

```bash
git add backend/apps/ocr/api backend/apps/ocr/services/confirmation.py backend/config/urls.py backend/tests/ocr/api
git commit -m "feat: add medicine OCR review APIs"
```

## Task 8: Delete Temporary Images And Add Safe Observability

**Files:**
- Create: `backend/apps/ocr/services/retention.py`
- Modify: `backend/apps/ocr/tasks.py`
- Modify: `backend/config/settings.py`
- Test: `backend/tests/ocr/services/test_retention.py`

- [ ] **Step 1: Write failing retention tests**

```python
# backend/tests/ocr/services/test_retention.py
from datetime import timedelta

import pytest
from django.utils import timezone

from apps.ocr.models import OCRJob
from apps.ocr.services.retention import delete_job_images, purge_expired_images


class FakeStorage:
    def __init__(self):
        self.deleted = []
    def delete(self, key):
        self.deleted.append(key)


@pytest.mark.django_db
def test_delete_clears_keys_after_all_objects_are_removed(user):
    job = OCRJob.objects.create(user=user, image_keys={"front": "a", "expiry": "b"})
    storage = FakeStorage()
    delete_job_images(job.id, storage=storage)
    job.refresh_from_db()
    assert storage.deleted == ["a", "b"]
    assert job.image_keys == {}


@pytest.mark.django_db
def test_purge_deletes_expired_unconfirmed_jobs(user):
    job = OCRJob.objects.create(user=user, image_keys={"front": "a"})
    OCRJob.objects.filter(id=job.id).update(expires_at=timezone.now() - timedelta(seconds=1))
    storage = FakeStorage()
    assert purge_expired_images(storage=storage) == 1
    assert storage.deleted == ["a"]
```

- [ ] **Step 2: Run tests and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/services/test_retention.py -q`

Expected: FAIL because the retention service does not exist.

- [ ] **Step 3: Implement idempotent deletion and periodic cleanup**

```python
# backend/apps/ocr/services/retention.py
from django.db import transaction
from django.utils import timezone

from apps.ocr.models import OCRJob


def delete_job_images(job_id, *, storage):
    job = OCRJob.objects.get(id=job_id)
    for key in job.image_keys.values():
        storage.delete(key)
    with transaction.atomic():
        locked = OCRJob.objects.select_for_update().get(id=job_id)
        locked.image_keys = {}
        locked.save(update_fields=["image_keys", "updated_at"])


def purge_expired_images(*, storage):
    ids = list(OCRJob.objects.filter(expires_at__lte=timezone.now()).exclude(image_keys={}).values_list("id", flat=True))
    for job_id in ids:
        delete_job_images(job_id, storage=storage)
    return len(ids)
```

Add these task entry points; S3 `delete_object` is already idempotent for a missing key, while any other exception leaves `image_keys` intact for the next run:

```python
# append to backend/apps/ocr/tasks.py
from apps.ocr.services.retention import delete_job_images, purge_expired_images


@shared_task
def delete_ocr_job_images(job_id):
    try:
        delete_job_images(job_id, storage=get_object_storage())
    except Exception:
        logger.exception("image_delete_failed", extra={"job_id": str(job_id), "error_code": "image_delete_failed"})
        raise


@shared_task
def purge_expired_ocr_images():
    return purge_expired_images(storage=get_object_storage())
```

```python
# append to backend/config/settings.py
CELERY_BEAT_SCHEDULE = {
    "purge-expired-ocr-images-hourly": {
        "task": "apps.ocr.tasks.purge_expired_ocr_images",
        "schedule": 3600.0,
    },
}
```

- [ ] **Step 4: Verify logs contain metadata but no recognized text**

Add a `caplog` test that processes a fake line containing `布洛芬缓释胶囊`, then assert the line is absent from `caplog.text` while `job_id`, `duration_ms`, and `line_count` are present.

Run: `.venv/bin/pytest backend/tests/ocr/services/test_retention.py backend/tests/ocr/test_tasks.py -q`

Expected: all tests pass.

- [ ] **Step 5: Commit privacy cleanup**

```bash
git add backend/apps/ocr/services/retention.py backend/apps/ocr/tasks.py backend/config/settings.py backend/tests/ocr
git commit -m "feat: purge temporary OCR images"
```

## Task 9: Add Flutter OCR Domain And API Client

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/features/medicine_ocr/domain/ocr_job.dart`
- Create: `app/lib/features/medicine_ocr/data/medicine_ocr_api.dart`
- Test: `app/test/medicine_ocr_api_test.dart`

- [ ] **Step 1: Add `image_picker` without overwriting current dependency edits**

Add `image_picker: ^1.1.2` under `dependencies`. Keep `flutter_local_notifications`, `http`, `timezone`, and all current user changes intact.

Run: `scripts/flutterw pub get`

Expected: `app/pubspec.lock` updates and dependency resolution succeeds.

- [ ] **Step 2: Write failing client tests for signed upload and polling payloads**

```dart
// app/test/medicine_ocr_api_test.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_ocr/data/medicine_ocr_api.dart';


http.Response jsonResponse(int status, Map<String, Object?> body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
http.Response emptyResponse(int status) => http.Response('', status);


class RecordingClient extends http.BaseClient {
  RecordingClient(this.responses);
  final List<http.Response> responses;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = responses.removeAt(0);
    return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, headers: response.headers);
  }
}


test('uploads two photos and creates an OCR job', () async {
  final client = RecordingClient([
    jsonResponse(201, {'object_key': 'front-key', 'upload_url': 'https://upload/front', 'headers': {'Content-Type': 'image/jpeg'}, 'expires_at': '2026-08-04T10:10:00Z'}),
    emptyResponse(200),
    jsonResponse(201, {'object_key': 'expiry-key', 'upload_url': 'https://upload/expiry', 'headers': {'Content-Type': 'image/jpeg'}, 'expires_at': '2026-08-04T10:10:00Z'}),
    emptyResponse(200),
    jsonResponse(201, {'id': 'job-1', 'status': 'queued'}),
  ]);
  final api = MedicineOcrApi(baseUrl: 'https://api.invalid', accessToken: 'token', client: client);
  final job = await api.createJob(frontBytes: [1, 2], expiryBytes: [3, 4]);
  expect(job.id, 'job-1');
  expect(client.requests.map((r) => r.method), ['POST', 'PUT', 'POST', 'PUT', 'POST']);
});
```

- [ ] **Step 3: Implement domain types and client methods**

```dart
// app/lib/features/medicine_ocr/domain/ocr_job.dart
class OcrCandidate {
  const OcrCandidate({required this.medicineName, required this.specification, required this.batchNumber, this.productionDate, this.expiryDate});
  final String medicineName;
  final String specification;
  final String batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;

  factory OcrCandidate.fromJson(Map<String, dynamic> json) => OcrCandidate(
    medicineName: json['medicine_name'] as String? ?? '',
    specification: json['specification'] as String? ?? '',
    batchNumber: json['batch_number'] as String? ?? '',
    productionDate: json['production_date'] == null ? null : DateTime.parse(json['production_date'] as String),
    expiryDate: json['expiry_date'] == null ? null : DateTime.parse(json['expiry_date'] as String),
  );
}

class OcrJob {
  const OcrJob({required this.id, required this.status, this.candidate, this.errorCode});
  final String id;
  final String status;
  final OcrCandidate? candidate;
  final String? errorCode;
  bool get isTerminal => status == 'succeeded' || status == 'failed' || status == 'confirmed';

  factory OcrJob.fromJson(Map<String, dynamic> json) => OcrJob(
    id: json['id'] as String,
    status: json['status'] as String,
    candidate: json['candidate'] == null ? null : OcrCandidate.fromJson(json['candidate'] as Map<String, dynamic>),
    errorCode: json['error_code'] as String?,
  );
}
```

```dart
// app/lib/features/medicine_ocr/data/medicine_ocr_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ocr_job.dart';


class _UploadGrant {
  const _UploadGrant(this.objectKey, this.url, this.headers);
  final String objectKey;
  final Uri url;
  final Map<String, String> headers;
}


class MedicineOcrApi {
  MedicineOcrApi({required this.baseUrl, required this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String accessToken;
  final http.Client _client;

  Map<String, String> get _apiHeaders => {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  };

  Future<_UploadGrant> _createUpload(String kind, List<int> bytes) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/ocr/uploads'),
      headers: _apiHeaders,
      body: jsonEncode({'kind': kind, 'content_type': 'image/jpeg', 'byte_length': bytes.length}),
    );
    if (response.statusCode != 201) throw MedicineOcrApiException(response.statusCode);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _UploadGrant(
      json['object_key'] as String,
      Uri.parse(json['upload_url'] as String),
      Map<String, String>.from(json['headers'] as Map),
    );
  }

  Future<String> _upload(String kind, List<int> bytes) async {
    final grant = await _createUpload(kind, bytes);
    final response = await _client.put(grant.url, headers: grant.headers, body: bytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MedicineOcrApiException(response.statusCode);
    }
    return grant.objectKey;
  }

  Future<OcrJob> createJob({required List<int> frontBytes, List<int>? expiryBytes}) async {
    final images = <Map<String, String>>[];
    images.add({'kind': 'front', 'object_key': await _upload('front', frontBytes)});
    if (expiryBytes != null) {
      images.add({'kind': 'expiry', 'object_key': await _upload('expiry', expiryBytes)});
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/ocr/jobs'),
      headers: _apiHeaders,
      body: jsonEncode({'images': images}),
    );
    if (response.statusCode != 201) throw MedicineOcrApiException(response.statusCode);
    return OcrJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<OcrJob> getJob(String id) async {
    final response = await _client.get(Uri.parse('$baseUrl/api/v1/ocr/jobs/$id'), headers: _apiHeaders);
    if (response.statusCode != 200) throw MedicineOcrApiException(response.statusCode);
    return OcrJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> confirmJob(String id, Map<String, Object?> fields) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/ocr/jobs/$id/confirm'),
      headers: _apiHeaders,
      body: jsonEncode(fields),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw MedicineOcrApiException(response.statusCode);
    }
  }

  void close() => _client.close();
}


class MedicineOcrApiException implements Exception {
  const MedicineOcrApiException(this.statusCode);
  final int statusCode;
}
```

API requests include the bearer token. Signed object-storage `PUT` requests include only returned upload headers and never forward the API authorization token to COS, OSS, or MinIO. Poll every two seconds in the screen, not recursively inside the client.

- [ ] **Step 4: Run client tests**

Run: `scripts/flutterw test app/test/medicine_ocr_api_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit Flutter data flow**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/features/medicine_ocr/domain app/lib/features/medicine_ocr/data app/test/medicine_ocr_api_test.dart
git commit -m "feat: add medicine OCR mobile client"
```

## Task 10: Build The Two-Photo Review And Confirmation UI

**Files:**
- Create: `app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart`
- Create: `app/lib/features/home/presentation/app_shell.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/medicine_ocr_screen_test.dart`

- [ ] **Step 1: Write failing widget tests for the complete user decision path**

```dart
// app/test/medicine_ocr_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_ocr/domain/ocr_job.dart';
import 'package:smart_reminder_app/features/medicine_ocr/presentation/medicine_ocr_screen.dart';


testWidgets('requires front photo, shows candidates, and confirms edited values', (tester) async {
  final captures = <String, List<int>>{'front': [1], 'expiry': [2]};
  Map<String, Object?>? confirmed;
  await tester.pumpWidget(MaterialApp(home: MedicineOcrScreen(
    capture: (kind) async => captures[kind],
    createJob: ({required frontBytes, expiryBytes}) async => const OcrJob(id: 'job-1', status: 'queued'),
    getJob: (_) async => OcrJob(id: 'job-1', status: 'succeeded', candidate: OcrCandidate(
      medicineName: '布洛芬缓释胶囊', specification: '0.3g*20粒', batchNumber: '', expiryDate: DateTime(2028, 5, 31),
    )),
    confirmJob: (_, fields) async { confirmed = fields; },
    pollInterval: Duration.zero,
  )));
  await tester.tap(find.text('拍摄药盒正面'));
  await tester.tap(find.text('拍摄有效期'));
  await tester.tap(find.text('开始识别'));
  await tester.pumpAndSettle();
  expect(find.text('核对识别结果'), findsOneWidget);
  await tester.enterText(find.byKey(const Key('medicine-name')), '布洛芬胶囊');
  await tester.tap(find.text('确认入库'));
  await tester.pumpAndSettle();
  expect(confirmed?['medicine_name'], '布洛芬胶囊');
});
```

- [ ] **Step 2: Run widget tests and verify RED**

Run: `scripts/flutterw test app/test/medicine_ocr_screen_test.dart`

Expected: FAIL because `MedicineOcrScreen` does not exist.

- [ ] **Step 3: Implement capture, stable progress, failure, and review states**

Use injected functions from the test. Production wiring uses `ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 2048)`. The screen has four explicit states:

```dart
enum MedicineOcrStage { capture, uploading, processing, review }
```

Implement the screen with injected boundaries and these state transitions:

```dart
// app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/ocr_job.dart';


enum MedicineOcrStage { capture, uploading, processing, review }

class MedicineOcrScreen extends StatefulWidget {
  const MedicineOcrScreen({
    required this.capture,
    required this.createJob,
    required this.getJob,
    required this.confirmJob,
    this.pollInterval = const Duration(seconds: 2),
    super.key,
  });
  final Future<List<int>?> Function(String kind) capture;
  final Future<OcrJob> Function({required List<int> frontBytes, List<int>? expiryBytes}) createJob;
  final Future<OcrJob> Function(String id) getJob;
  final Future<void> Function(String id, Map<String, Object?> fields) confirmJob;
  final Duration pollInterval;

  @override
  State<MedicineOcrScreen> createState() => _MedicineOcrScreenState();
}

class _MedicineOcrScreenState extends State<MedicineOcrScreen> {
  final _name = TextEditingController();
  final _specification = TextEditingController();
  final _batch = TextEditingController();
  final _production = TextEditingController();
  final _expiry = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  MedicineOcrStage _stage = MedicineOcrStage.capture;
  List<int>? _frontBytes;
  List<int>? _expiryBytes;
  OcrJob? _job;
  String? _error;
  bool _cancelPolling = false;

  @override
  void dispose() {
    _cancelPolling = true;
    for (final controller in [_name, _specification, _batch, _production, _expiry, _quantity]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _capture(String kind) async {
    final bytes = await widget.capture(kind);
    if (!mounted || bytes == null) return;
    setState(() {
      if (kind == 'front') _frontBytes = bytes;
      if (kind == 'expiry') _expiryBytes = bytes;
      _error = null;
    });
  }

  Future<void> _start() async {
    final front = _frontBytes;
    if (front == null || _stage != MedicineOcrStage.capture) return;
    setState(() { _stage = MedicineOcrStage.uploading; _error = null; });
    try {
      final created = await widget.createJob(frontBytes: front, expiryBytes: _expiryBytes);
      if (!mounted) return;
      setState(() { _job = created; _stage = MedicineOcrStage.processing; });
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!_cancelPolling && DateTime.now().isBefore(deadline)) {
        final current = await widget.getJob(created.id);
        if (!mounted || _cancelPolling) return;
        if (current.status == 'succeeded' && current.candidate != null) {
          _loadCandidate(current.candidate!);
          setState(() { _job = current; _stage = MedicineOcrStage.review; });
          return;
        }
        if (current.status == 'failed') {
          setState(() { _stage = MedicineOcrStage.capture; _error = '识别失败，可以重拍或手动录入'; });
          return;
        }
        await Future<void>.delayed(widget.pollInterval);
      }
      if (mounted) setState(() { _stage = MedicineOcrStage.capture; _error = '识别仍在处理中，请稍后重试'; });
    } catch (_) {
      if (mounted) setState(() { _stage = MedicineOcrStage.capture; _error = '上传失败，请检查网络后重试'; });
    }
  }

  void _loadCandidate(OcrCandidate value) {
    _name.text = value.medicineName;
    _specification.text = value.specification;
    _batch.text = value.batchNumber;
    _production.text = value.productionDate?.toIso8601String().substring(0, 10) ?? '';
    _expiry.text = value.expiryDate?.toIso8601String().substring(0, 10) ?? '';
  }

  bool get _canConfirm {
    if (_name.text.trim().isEmpty) return false;
    final production = DateTime.tryParse(_production.text.trim());
    final expiry = DateTime.tryParse(_expiry.text.trim());
    return production == null || expiry == null || !expiry.isBefore(production);
  }

  Future<void> _confirm() async {
    final job = _job;
    if (job == null || !_canConfirm) return;
    await widget.confirmJob(job.id, {
      'medicine_name': _name.text.trim(),
      'specification': _specification.text.trim(),
      'batch_number': _batch.text.trim(),
      'production_date': _production.text.trim().isEmpty ? null : _production.text.trim(),
      'expiry_date': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
      'quantity': int.tryParse(_quantity.text) ?? 1,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入药箱')));
    setState(() { _stage = MedicineOcrStage.capture; _frontBytes = null; _expiryBytes = null; _job = null; });
  }

  Widget _captureView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    OutlinedButton.icon(onPressed: () => _capture('front'), icon: const Icon(Icons.camera_alt_outlined), label: Text(_frontBytes == null ? '拍摄药盒正面' : '重新拍摄药盒正面')),
    const SizedBox(height: 12),
    OutlinedButton.icon(onPressed: () => _capture('expiry'), icon: const Icon(Icons.event_outlined), label: Text(_expiryBytes == null ? '拍摄有效期' : '重新拍摄有效期')),
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    const SizedBox(height: 20),
    SizedBox(height: 48, child: FilledButton.icon(onPressed: _frontBytes == null ? null : _start, icon: const Icon(Icons.document_scanner_outlined), label: const Text('开始识别'))),
  ]);

  Widget _reviewView() => Form(onChanged: () => setState(() {}), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('核对识别结果', style: Theme.of(context).textTheme.titleLarge),
    TextFormField(key: const Key('medicine-name'), controller: _name, decoration: const InputDecoration(labelText: '药品名称')),
    TextFormField(controller: _specification, decoration: const InputDecoration(labelText: '规格')),
    TextFormField(controller: _batch, decoration: const InputDecoration(labelText: '批号')),
    TextFormField(controller: _production, decoration: const InputDecoration(labelText: '生产日期', hintText: 'YYYY-MM-DD')),
    TextFormField(controller: _expiry, decoration: const InputDecoration(labelText: '有效期', hintText: 'YYYY-MM-DD')),
    TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '数量')),
    const SizedBox(height: 20),
    SizedBox(height: 48, child: FilledButton.icon(onPressed: _canConfirm ? _confirm : null, icon: const Icon(Icons.check), label: const Text('确认入库'))),
  ]));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('药盒识别')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      if (_stage == MedicineOcrStage.capture) _captureView(),
      if (_stage == MedicineOcrStage.uploading) const Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在上传图片')])),
      if (_stage == MedicineOcrStage.processing) const Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在识别')])),
      if (_stage == MedicineOcrStage.review) _reviewView(),
    ]),
  );
}
```

The front image is required and the expiry image is recommended. Local image bytes remain available after upload or OCR failure so the user can retry. Polling stops on a terminal state, on disposal, or after 60 seconds while leaving the server job intact.

- [ ] **Step 4: Add app navigation without touching reminder feature files**

Create the shell without modifying reminder feature files:

```dart
// app/lib/features/home/presentation/app_shell.dart
import 'package:flutter/material.dart';


class AppShell extends StatefulWidget {
  const AppShell({required this.reminders, required this.medicineOcr, super.key});
  final Widget reminders;
  final Widget medicineOcr;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: [widget.reminders, widget.medicineOcr]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.alarm_outlined), selectedIcon: Icon(Icons.alarm), label: '提醒'),
        NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication), label: '药箱录入'),
      ],
    ),
  );
}
```

In `main.dart`, construct `MedicineOcrApi` beside the existing reminder client, pass both screens to `AppShell`, close both clients in `dispose`, and wire capture exactly as follows:

```dart
Future<List<int>?> _captureMedicineImage(String kind) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 82,
    maxWidth: 2048,
  );
  return image?.readAsBytes();
}
```

- [ ] **Step 5: Run widget tests and analyzer**

Run: `scripts/flutterw test app/test/medicine_ocr_screen_test.dart app/test/reminder_composer_screen_test.dart`

Expected: all OCR and existing reminder widget tests pass.

Run: `scripts/flutterw analyze`

Expected: `No issues found!`.

- [ ] **Step 6: Commit the mobile review flow**

```bash
git add app/lib/features/medicine_ocr/presentation app/lib/features/home app/lib/main.dart app/test/medicine_ocr_screen_test.dart
git commit -m "feat: add medicine OCR confirmation flow"
```

## Task 11: Isolate The OCR Runtime And Add A Real Smoke Check

**Files:**
- Create: `backend/Dockerfile.ocr`
- Create: `backend/apps/ocr/management/commands/check_ocr.py`
- Modify: `compose.yaml`
- Modify: `docs/local-development.mmd`
- Modify: `README.md`
- Test: `backend/tests/ocr/test_smoke_command.py`

- [ ] **Step 1: Write a failing management-command test with an injected provider**

```python
# backend/tests/ocr/test_smoke_command.py
from django.core.management import call_command


def test_check_ocr_reports_line_count(mocker, capsys):
    provider = mocker.patch("apps.ocr.management.commands.check_ocr.get_ocr_provider").return_value
    provider.recognize.return_value.lines = (object(),)
    call_command("check_ocr", "backend/tests/ocr/fixtures/medicine_front.jpg")
    assert "OCR smoke check passed: 1 lines" in capsys.readouterr().out
```

- [ ] **Step 2: Run the test and verify RED**

Run: `.venv/bin/pytest backend/tests/ocr/test_smoke_command.py -q`

Expected: FAIL with `Unknown command: 'check_ocr'`.

- [ ] **Step 3: Add the OCR image and smoke command**

```dockerfile
# backend/Dockerfile.ocr
FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY backend/requirements /app/backend/requirements
RUN pip install --no-cache-dir -r /app/backend/requirements/ocr.txt
COPY backend /app/backend
WORKDIR /app/backend
CMD ["celery", "-A", "config", "worker", "-Q", "ocr", "--concurrency=1", "--prefetch-multiplier=1", "--loglevel=INFO"]
```

`check_ocr` reads the supplied fixture bytes, calls `get_ocr_provider().recognize(..., role="front")`, exits nonzero when no lines are returned, and prints only the count and elapsed milliseconds. It never prints text values.

```python
# backend/apps/ocr/management/commands/check_ocr.py
import time
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from apps.ocr.providers.factory import get_ocr_provider


class Command(BaseCommand):
    help = "Load the configured OCR model and recognize a non-sensitive fixture"

    def add_arguments(self, parser):
        parser.add_argument("image_path")

    def handle(self, *args, **options):
        image_path = Path(options["image_path"])
        if not image_path.is_file():
            raise CommandError("OCR smoke fixture does not exist")
        started = time.monotonic()
        result = get_ocr_provider().recognize(image_path.read_bytes(), role="front")
        if not result.lines:
            raise CommandError("OCR smoke check returned no lines")
        elapsed_ms = int((time.monotonic() - started) * 1000)
        self.stdout.write(f"OCR smoke check passed: {len(result.lines)} lines; {elapsed_ms} ms")
```

- [ ] **Step 4: Split the Compose worker and apply resource limits**

Rename the existing generic `worker` service to `worker`, route it away from `ocr`, and add:

```yaml
  ocr-worker:
    build:
      context: .
      dockerfile: backend/Dockerfile.ocr
    environment: *backend_environment
    command: celery -A config worker -Q ocr --concurrency=1 --prefetch-multiplier=1 --loglevel=INFO
    mem_reservation: 700m
    mem_limit: 1200m
    cpus: 1.0
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
```

The generic worker command becomes `celery -A config worker -Q celery --loglevel=INFO` so OCR models cannot load there.

- [ ] **Step 5: Build and run the real model smoke check**

Run: `docker compose build api ocr-worker`

Expected: both images build; the API image does not install `onnxruntime` or `rapidocr`.

Run: `docker compose run --rm ocr-worker python manage.py check_ocr tests/ocr/fixtures/medicine_front.jpg`

Expected: exits `0` and prints `OCR smoke check passed: <positive count> lines` without printing recognized text.

- [ ] **Step 6: Document local, Tencent Cloud, and Alibaba Cloud operations**

Add the exact environment block and runtime checklist from this plan to `docs/local-development.mmd`. Add API rows for upload, create job, get job, and confirm to `README.md`, plus the command for starting only OCR dependencies:

```bash
docker compose up -d postgres redis minio api ocr-worker beat
docker compose exec ocr-worker python manage.py check_ocr tests/ocr/fixtures/medicine_front.jpg
```

- [ ] **Step 7: Commit deployment support**

```bash
git add backend/Dockerfile.ocr backend/apps/ocr/management backend/tests/ocr/test_smoke_command.py compose.yaml docs/local-development.mmd README.md
git commit -m "ops: isolate and verify RapidOCR worker"
```

## Task 12: Run The Complete Release Gate

**Files:**
- Modify only files required to fix failures introduced by Tasks 1-11.

- [ ] **Step 1: Run all backend tests**

Run: `.venv/bin/pytest backend/tests -q`

Expected: all existing reminder tests and new OCR tests pass.

- [ ] **Step 2: Run Django deployment checks and migration drift check**

Run: `.venv/bin/python backend/manage.py check`

Expected: `System check identified no issues`.

Run: `.venv/bin/python backend/manage.py makemigrations --check --dry-run`

Expected: `No changes detected`.

- [ ] **Step 3: Run all Flutter checks**

Run: `scripts/flutterw analyze && scripts/flutterw test`

Expected: analyzer reports no issues and all tests pass, including existing notification tests.

- [ ] **Step 4: Validate Compose and OCR isolation**

Run: `docker compose config --quiet`

Expected: exits `0`.

Run: `docker compose run --rm api python -c "import importlib.util; assert importlib.util.find_spec('rapidocr') is None"`

Expected: exits `0`, proving the API image does not contain OCR dependencies.

Run: `docker compose run --rm ocr-worker python manage.py check_ocr tests/ocr/fixtures/medicine_front.jpg`

Expected: smoke check passes with a positive line count.

- [ ] **Step 5: Manually verify the privacy and confirmation gates**

Use a synthetic medicine box photo and confirm all of the following:

- Upload URLs expire after ten minutes and objects are not publicly readable.
- A user cannot create or fetch a job with another user's key or job ID.
- OCR candidates never create inventory before the confirm request.
- Editing the recognized medicine name or date changes the confirmed inventory values.
- A repeated confirm request returns the same inventory batch.
- Confirmation deletes both images; failed or abandoned jobs are deleted by the 24-hour task and the COS/OSS lifecycle fallback.
- Application logs contain no full recognized text, image bytes, signed URL, AccessKey, prescription, or medicine note.

- [ ] **Step 6: Verify the final diff is mechanically clean**

Run: `git diff --check`

Expected: no output and exit code `0`. If a release-gate failure required code changes, return to the owning task, rerun that task's focused test, and use that task's explicit `git add` and commit command. Do not create a catch-all commit and do not include pre-existing unrelated Flutter or IDE changes.

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.ocr.domain.layout import merge_documents
from apps.ocr.models import OCRCandidate, OCRJob

from .candidate_resolver import resolve_candidates
from .debug_logging import log_ocr_documents
from .image_validation import prepare_ocr_variants


def run_job(job_id, *, storage, provider, semantic_provider=None):
    with transaction.atomic():
        job = OCRJob.objects.select_for_update().get(id=job_id)
        # Celery 重投或客户端重复触发时，成功任务直接返回，避免重复识别和写入。
        if job.status in {
            OCRJob.Status.SUCCEEDED,
            OCRJob.Status.CONFIRMED,
        }:
            return job
        job.status = OCRJob.Status.RUNNING
        job.attempt_count += 1
        job.error_code = ""
        job.save(
            update_fields=[
                "status",
                "attempt_count",
                "error_code",
                "updated_at",
            ]
        )

    documents = []
    for role in ("front", "expiry"):
        key = job.image_keys.get(role)
        if not key:
            continue
        variants = prepare_ocr_variants(storage.get_bytes(key), role=role)
        recognized = tuple(
            provider.recognize(image, role=role) for image in variants
        )
        documents.append(merge_documents(role, recognized))

    merged_documents = tuple(documents)
    log_ocr_documents(
        job_id,
        merged_documents,
        enabled=settings.OCR_DEBUG_TEXT_LOGGING,
    )
    candidates = resolve_candidates(
        merged_documents,
        semantic_provider=semantic_provider,
        reference_date=timezone.localdate(),
    )
    line_count = sum(len(document.lines) for document in documents)

    with transaction.atomic():
        job = OCRJob.objects.select_for_update().get(id=job_id)
        # 只持久化结构化候选值和置信度，完整 OCR 原文不进入数据库。
        OCRCandidate.objects.update_or_create(
            job=job,
            defaults={
                "medicine_name": candidates.medicine_name,
                "specification": candidates.specification,
                "manufacturer": candidates.manufacturer,
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

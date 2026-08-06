from django.conf import settings
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.ocr.models import OCRJob
from apps.ocr.providers.storage import get_object_storage
from apps.ocr.services.confirmation import confirm_job
from apps.ocr.services.uploads import create_upload
from apps.ocr.tasks import delete_ocr_job_images, process_ocr_job

from .serializers import (
    ConfirmCandidateSerializer,
    CreateJobSerializer,
    UploadRequestSerializer,
)


def _candidate_payload(job):
    if not hasattr(job, "candidate"):
        return None
    value = job.candidate
    return {
        "medicine_name": value.medicine_name,
        "specification": value.specification,
        "batch_number": value.batch_number,
        "production_date": (
            value.production_date.isoformat()
            if value.production_date
            else None
        ),
        "expiry_date": (
            value.expiry_date.isoformat() if value.expiry_date else None
        ),
        "confidence": value.confidence_json,
    }


class OCRDisabled(APIException):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    default_detail = {"code": "ocr_disabled"}
    default_code = "ocr_disabled"


class OcrEnabledAPIView(APIView):
    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if not settings.OCR_ENABLED:
            raise OCRDisabled()


class UploadView(OcrEnabledAPIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = UploadRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            grant = create_upload(
                user=request.user,
                storage=get_object_storage(),
                **serializer.validated_data,
            )
        except ValueError as exc:
            return Response(
                {"code": str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(
            {
                "object_key": grant.object_key,
                "upload_url": grant.upload_url,
                "headers": grant.headers,
                "expires_at": grant.expires_at.isoformat(),
            },
            status=status.HTTP_201_CREATED,
        )


class JobListCreateView(OcrEnabledAPIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateJobSerializer(
            data=request.data,
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        image_keys = {
            value["kind"]: value["object_key"]
            for value in serializer.validated_data["images"]
        }
        with transaction.atomic():
            job = OCRJob.objects.create(
                user=request.user,
                image_keys=image_keys,
            )
            transaction.on_commit(
                lambda: process_ocr_job.delay(str(job.id))
            )
        return Response(
            {"id": str(job.id), "status": job.status},
            status=status.HTTP_201_CREATED,
        )


class JobDetailView(OcrEnabledAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, job_id):
        job = get_object_or_404(
            OCRJob.objects.select_related("candidate"),
            id=job_id,
            user=request.user,
        )
        payload = {"id": str(job.id), "status": job.status}
        if job.status == OCRJob.Status.SUCCEEDED:
            payload["candidate"] = _candidate_payload(job)
        if job.status == OCRJob.Status.FAILED:
            payload["error_code"] = job.error_code
        return Response(payload)


class JobConfirmView(OcrEnabledAPIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, job_id):
        serializer = ConfirmCandidateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            batch, created = confirm_job(
                job_id=job_id,
                user=request.user,
                fields=serializer.validated_data,
            )
        except OCRJob.DoesNotExist:
            return Response(
                {"detail": "未找到该 OCR 任务"},
                status=status.HTTP_404_NOT_FOUND,
            )
        except ValueError as exc:
            return Response(
                {"code": str(exc)},
                status=status.HTTP_409_CONFLICT,
            )

        if created:
            transaction.on_commit(
                lambda: delete_ocr_job_images.delay(str(job_id))
            )
        return Response(
            {
                "medicine_id": str(batch.medicine_id),
                "inventory_batch_id": str(batch.id),
                "status": "confirmed",
            },
            status=(
                status.HTTP_201_CREATED
                if created
                else status.HTTP_200_OK
            ),
        )

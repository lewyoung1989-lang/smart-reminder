import logging
from datetime import date

from django.db import transaction
from django.db.models import DateField, Q, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.generics import DestroyAPIView, ListAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.medicines.models import ExpiryAlertState, ExpiryBatchAction, InventoryBatch
from apps.medicines.services.expiry_alerts import refresh_expiry_alerts

from .pagination import InventoryBatchCursorPagination
from .serializers import (
    ExpiryBatchActionSerializer,
    ExpiryDateCorrectionSerializer,
    InventoryBatchSerializer,
)


logger = logging.getLogger(__name__)


class InventoryBatchListView(ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = InventoryBatchSerializer
    pagination_class = InventoryBatchCursorPagination

    def get_queryset(self):
        query = self.request.query_params.get("q", "").strip()
        if len(query) > 100:
            raise ValidationError({"q": "搜索内容不能超过 100 个字符"})

        queryset = InventoryBatch.objects.filter(
            medicine__owner=self.request.user
        ).select_related("medicine")
        if query:
            queryset = queryset.filter(
                Q(medicine__name__icontains=query)
                | Q(medicine__specification__icontains=query)
                | Q(batch_number__icontains=query)
            )
        return queryset.annotate(
            expiry_sort=Coalesce(
                "expiry_date",
                Value(date.max, output_field=DateField()),
                output_field=DateField(),
            )
        )


class InventoryBatchDestroyView(DestroyAPIView):
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return InventoryBatch.objects.filter(medicine__owner=self.request.user)

    def perform_destroy(self, instance):
        batch_id = instance.id
        instance.delete()
        logger.info("inventory_batch_deleted batch_id=%s", batch_id)


class InventoryBatchExpiryActionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        serializer = ExpiryBatchActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data["action"]

        with transaction.atomic():
            try:
                batch = (
                    InventoryBatch.objects.select_for_update()
                    .select_related("medicine")
                    .get(id=pk, medicine__owner=request.user)
                )
            except InventoryBatch.DoesNotExist:
                return Response(
                    {"detail": "未找到库存批次"}, status=status.HTTP_404_NOT_FOUND
                )

            now = timezone.now()
            ExpiryAlertState.objects.filter(
                batch=batch,
                status=ExpiryAlertState.Status.ACTIVE,
            ).update(status=ExpiryAlertState.Status.RESOLVED, resolved_at=now)
            audit = ExpiryBatchAction(batch=batch, user=request.user, action=action)
            audit.full_clean()
            audit.save()

        return Response(
            {"batch_id": str(batch.id), "action": action}, status=status.HTTP_200_OK
        )


class InventoryBatchExpiryDateCorrectionView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        serializer = ExpiryDateCorrectionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        changes = serializer.validated_data

        with transaction.atomic():
            try:
                batch = (
                    InventoryBatch.objects.select_for_update()
                    .select_related("medicine")
                    .get(id=pk, medicine__owner=request.user)
                )
            except InventoryBatch.DoesNotExist:
                return Response(
                    {"detail": "未找到库存批次"}, status=status.HTTP_404_NOT_FOUND
                )

            original = {
                "expiry_date": batch.expiry_date,
                "opened_at": batch.opened_at,
                "opened_shelf_life_days": batch.opened_shelf_life_days,
            }
            for field, value in changes.items():
                setattr(batch, field, value)

            if batch.production_date and batch.expiry_date and batch.expiry_date < batch.production_date:
                raise ValidationError({"expiry_date": ["有效期不能早于生产日期。"]})
            batch.full_clean()

            changed_fields = [
                field for field, old_value in original.items() if getattr(batch, field) != old_value
            ]
            if changed_fields:
                batch.save(update_fields=changed_fields)
                refresh_expiry_alerts(batch=batch, today=timezone.localdate())
                audit = ExpiryBatchAction(
                    batch=batch,
                    user=request.user,
                    action=ExpiryBatchAction.Action.CORRECTED,
                    change_json={
                        field: {
                            "old": _json_value(original[field]),
                            "new": _json_value(getattr(batch, field)),
                        }
                        for field in changed_fields
                    },
                )
                audit.full_clean()
                audit.save()

        return Response(InventoryBatchSerializer(batch).data, status=status.HTTP_200_OK)


def _json_value(value):
    return value.isoformat() if hasattr(value, "isoformat") else value

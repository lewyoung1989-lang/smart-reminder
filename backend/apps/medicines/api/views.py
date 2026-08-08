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

from .pagination import InventoryBatchCursorPagination
from .serializers import ExpiryBatchActionSerializer, InventoryBatchSerializer


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

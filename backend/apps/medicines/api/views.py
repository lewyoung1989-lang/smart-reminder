import logging
from datetime import date

from django.db.models import DateField, Q, Value
from django.db.models.functions import Coalesce
from rest_framework.exceptions import ValidationError
from rest_framework.generics import DestroyAPIView, ListAPIView
from rest_framework.permissions import IsAuthenticated

from apps.medicines.models import InventoryBatch

from .pagination import InventoryBatchCursorPagination
from .serializers import InventoryBatchSerializer


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

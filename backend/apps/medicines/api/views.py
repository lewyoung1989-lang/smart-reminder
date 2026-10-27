import logging
from datetime import date
from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError as ModelValidationError
from django.db import transaction
from django.db.models import DateField, F, Q, Value
from django.db.models.functions import Coalesce
from django.http import Http404
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.generics import DestroyAPIView, ListAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.medicines.models import (
    ExpiryAlertState,
    ExpiryBatchAction,
    InventoryBatch,
    MedicineItem,
    LowStockAlertState,
)
from apps.medicines.providers import (
    DeepSeekMedicineDescriptionError,
    DeepSeekMedicineDescriptionProvider,
)
from apps.medicines.services.expiry_alerts import refresh_expiry_alerts
from apps.medicines.services.low_stock_alerts import (
    refresh_low_stock_alerts_for_batch,
    refresh_low_stock_alerts_for_medicine,
    resolve_low_stock_alert,
)
from apps.medicines.services.access import (
    inventory_access_query,
    require_batch_access,
    resolve_inventory_scope,
)
from apps.medicines.services.photos import create_medicine_photo_upload
from apps.families.services import record_event
from apps.ocr.providers.storage import get_object_storage

from .pagination import InventoryBatchCursorPagination
from .serializers import (
    ExpiryBatchActionSerializer,
    ExpiryDateCorrectionSerializer,
    InventoryBatchCreateSerializer,
    InventoryBatchSerializer,
    InventoryBatchUpdateSerializer,
    LowStockAlertActionSerializer,
    MedicineDescriptionParseSerializer,
    MedicinePhotoUploadSerializer,
)


logger = logging.getLogger(__name__)


def _locked_accessible_batch_queryset(user):
    return (
        InventoryBatch.objects.select_for_update(of=("self",))
        .select_related("medicine")
        .filter(inventory_access_query(user))
    )


class MedicineDescriptionParseView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = MedicineDescriptionParseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if not settings.DEEPSEEK_API_KEY:
            return Response(
                {"detail": "智能解析暂不可用"},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        provider = DeepSeekMedicineDescriptionProvider(
            api_key=settings.DEEPSEEK_API_KEY,
            base_url=settings.DEEPSEEK_BASE_URL,
            model=settings.DEEPSEEK_MODEL,
            timeout_seconds=settings.DEEPSEEK_TIMEOUT_SECONDS,
        )
        try:
            draft = provider.parse(
                serializer.validated_data["text"],
                today=timezone.localdate(),
            )
        except DeepSeekMedicineDescriptionError:
            logger.warning("medicine_description_parse_failed")
            return Response(
                {"detail": "智能解析失败，请稍后重试"},
                status=status.HTTP_502_BAD_GATEWAY,
            )
        return Response(draft.model_dump(mode="json"), status=status.HTTP_200_OK)


class InventoryBatchListView(ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = InventoryBatchSerializer
    pagination_class = InventoryBatchCursorPagination

    def get_queryset(self):
        query = self.request.query_params.get("q", "").strip()
        if len(query) > 100:
            raise ValidationError({"q": "搜索内容不能超过 100 个字符"})

        scope = self.request.query_params.get("scope", "personal")
        ownership = resolve_inventory_scope(self.request.user, scope)
        queryset = InventoryBatch.objects.filter(
            medicine__owner=ownership["owner"],
            medicine__family=ownership["family"],
        ).select_related("medicine")
        if query:
            queryset = queryset.filter(
                Q(medicine__name__icontains=query)
                | Q(medicine__specification__icontains=query)
                | Q(medicine__manufacturer__icontains=query)
                | Q(batch_number__icontains=query)
            )
        return queryset.annotate(
            expiry_sort=Coalesce(
                "expiry_date",
                Value(date.max, output_field=DateField()),
                output_field=DateField(),
            )
        )

    def post(self, request):
        serializer = InventoryBatchCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            batch = serializer.create_for_user(request.user)
            refresh_expiry_alerts(batch=batch, today=timezone.localdate())
            refresh_low_stock_alerts_for_batch(
                batch=batch,
                today=timezone.localdate(),
            )
        logger.info("inventory_batch_created batch_id=%s", batch.id)
        return Response(
            InventoryBatchSerializer(
                batch,
                context={
                    "object_storage": get_object_storage(),
                    "request": request,
                },
            ).data,
            status=status.HTTP_201_CREATED,
        )


class MedicinePhotoUploadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = MedicinePhotoUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            grant = create_medicine_photo_upload(
                user=request.user,
                storage=get_object_storage(),
                **serializer.validated_data,
            )
        except ValueError as exc:
            return Response({"code": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(
            {
                "object_key": grant.object_key,
                "upload_url": grant.upload_url,
                "headers": grant.headers,
                "expires_at": grant.expires_at.isoformat(),
            },
            status=status.HTTP_201_CREATED,
        )


class InventoryBatchDestroyView(DestroyAPIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        with transaction.atomic():
            accessible = self.get_object()
            batches = list(
                _locked_accessible_batch_queryset(request.user)
                .filter(medicine_id=accessible.medicine_id)
                .order_by("id")
            )
            batch = next((item for item in batches if item.id == pk), None)
            if batch is None:
                raise Http404
            require_batch_access(batch, request.user)
            medicine = MedicineItem.objects.select_for_update().get(
                id=batch.medicine_id
            )
            serializer = InventoryBatchUpdateSerializer(batch, data=request.data)
            serializer.is_valid(raise_exception=True)
            changes = dict(serializer.validated_data)
            if changes.pop("version") != batch.version:
                return Response(
                    {"code": "inventory_version_conflict", "version": batch.version},
                    status=status.HTTP_409_CONFLICT,
                )

            audit_changes = {}
            medicine_fields = []
            for field, api_field in (
                ("name", "medicine_name"),
                ("specification", "specification"),
                ("manufacturer", "manufacturer"),
            ):
                if api_field not in changes:
                    continue
                value = changes.pop(api_field)
                if value != getattr(medicine, field):
                    audit_changes[api_field] = {
                        "old": getattr(medicine, field), "new": value,
                    }
                    setattr(medicine, field, value)
                    medicine_fields.append(field)
            batch_fields = []
            for field, value in changes.items():
                if value != getattr(batch, field):
                    audit_changes[field] = {
                        "old": _json_value(getattr(batch, field)),
                        "new": _json_value(value),
                    }
                    setattr(batch, field, value)
                    batch_fields.append(field)

            try:
                medicine.full_clean()
                batch.full_clean()
            except ModelValidationError as error:
                raise ValidationError(error.message_dict) from error

            if audit_changes:
                if medicine_fields:
                    medicine.save(update_fields=medicine_fields)
                    InventoryBatch.objects.filter(medicine=medicine).exclude(
                        id=batch.id
                    ).update(version=F("version") + 1)
                batch.version += 1
                batch.updated_by = request.user
                batch.save(update_fields=[
                    *batch_fields, "version", "updated_by", "updated_at",
                ])
                batch.medicine = medicine
                ExpiryBatchAction.objects.create(
                    batch=batch,
                    user=request.user,
                    action=ExpiryBatchAction.Action.CORRECTED,
                    change_json=audit_changes,
                )
                refresh_expiry_alerts(batch=batch, today=timezone.localdate())
                refresh_low_stock_alerts_for_medicine(
                    medicine=medicine, today=timezone.localdate(),
                )
                if medicine.family_id:
                    record_event(
                        family=medicine.family,
                        actor=request.user,
                        event_type="inventory_corrected",
                        payload={"batch_id": str(batch.id), "version": batch.version},
                    )
            return Response(
                InventoryBatchSerializer(batch, context={"request": request}).data
            )

    def get_queryset(self):
        return InventoryBatch.objects.filter(
            inventory_access_query(self.request.user)
        ).distinct().select_related("medicine")

    def perform_destroy(self, instance):
        require_batch_access(instance, self.request.user, delete=True)
        batch_id = instance.id
        medicine = instance.medicine
        family = instance.medicine.family
        if family is not None:
            record_event(
                family=family,
                actor=self.request.user,
                event_type="inventory_deleted",
                payload={"batch_id": str(batch_id)},
            )
        instance.delete()
        refresh_low_stock_alerts_for_medicine(
            medicine=medicine,
            today=timezone.localdate(),
        )
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
                    _locked_accessible_batch_queryset(request.user)
                    .get(id=pk)
                )
            except InventoryBatch.DoesNotExist:
                return Response(
                    {"detail": "未找到库存批次"}, status=status.HTTP_404_NOT_FOUND
                )
            require_batch_access(batch, request.user)

            now = timezone.now()
            ExpiryAlertState.objects.filter(
                batch=batch,
                status=ExpiryAlertState.Status.ACTIVE,
            ).update(status=ExpiryAlertState.Status.RESOLVED, resolved_at=now)
            audit = ExpiryBatchAction(batch=batch, user=request.user, action=action)
            audit.full_clean()
            audit.save()
            if batch.medicine.family_id:
                record_event(
                    family=batch.medicine.family,
                    actor=request.user,
                    event_type="expiry_handled",
                    payload={"batch_id": str(batch.id), "action": action},
                )

        return Response(
            {"batch_id": str(batch.id), "action": action}, status=status.HTTP_200_OK
        )


class LowStockAlertActionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        serializer = LowStockAlertActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            try:
                alert = (
                    LowStockAlertState.objects.select_for_update()
                    .filter(
                        Q(medicine__owner=request.user)
                        | Q(medicine__family__members__user=request.user)
                    )
                    .distinct()
                    .get(id=pk)
                )
            except LowStockAlertState.DoesNotExist:
                return Response(
                    {"detail": "未找到低库存提醒"}, status=status.HTTP_404_NOT_FOUND
                )
            resolve_low_stock_alert(alert=alert)

        return Response({"alert_id": str(alert.id), "action": "handled"})


class InventoryBatchExpiryDateCorrectionView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        serializer = ExpiryDateCorrectionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        changes = serializer.validated_data

        with transaction.atomic():
            try:
                batch = (
                    _locked_accessible_batch_queryset(request.user)
                    .get(id=pk)
                )
            except InventoryBatch.DoesNotExist:
                return Response(
                    {"detail": "未找到库存批次"}, status=status.HTTP_404_NOT_FOUND
                )
            require_batch_access(batch, request.user)

            expected_version = request.data.get("version")
            if expected_version is not None and expected_version != batch.version:
                return Response(
                    {"code": "inventory_version_conflict", "version": batch.version},
                    status=status.HTTP_409_CONFLICT,
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
                batch.version += 1
                batch.updated_by = request.user
                batch.save(update_fields=[*changed_fields, "version", "updated_by", "updated_at"])
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
                if batch.medicine.family_id:
                    record_event(
                        family=batch.medicine.family,
                        actor=request.user,
                        event_type="inventory_corrected",
                        payload={
                            "batch_id": str(batch.id),
                            "version": batch.version,
                        },
                    )

        return Response(
            InventoryBatchSerializer(batch, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )


def _json_value(value):
    if isinstance(value, Decimal):
        return str(value)
    return value.isoformat() if hasattr(value, "isoformat") else value

from datetime import timedelta
from functools import cached_property
from zoneinfo import ZoneInfo

from django.utils import timezone
from rest_framework import serializers

from apps.medicines.models import ExpiryBatchAction, InventoryBatch, MedicineItem


class ExpiryBatchActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=ExpiryBatchAction.Action.choices)


class ExpiryDateCorrectionSerializer(serializers.Serializer):
    expiry_date = serializers.DateField(required=False, allow_null=True)
    opened_at = serializers.DateField(required=False, allow_null=True)
    opened_shelf_life_days = serializers.IntegerField(
        required=False,
        allow_null=True,
        min_value=1,
    )

    def validate(self, attrs):
        if not attrs:
            raise serializers.ValidationError({"detail": "至少需要提交一个修正字段。"})
        return attrs


class InventoryBatchCreateSerializer(serializers.Serializer):
    medicine_name = serializers.CharField(max_length=200, trim_whitespace=True)
    specification = serializers.CharField(
        max_length=120,
        required=False,
        allow_blank=True,
        trim_whitespace=True,
    )
    batch_number = serializers.CharField(
        max_length=100,
        required=False,
        allow_blank=True,
        trim_whitespace=True,
    )
    production_date = serializers.DateField(required=False, allow_null=True)
    expiry_date = serializers.DateField(required=False, allow_null=True)
    quantity = serializers.IntegerField(required=False, min_value=1, max_value=9999)

    def validate(self, attrs):
        production_date = attrs.get("production_date")
        expiry_date = attrs.get("expiry_date")
        if production_date and expiry_date and expiry_date < production_date:
            raise serializers.ValidationError(
                {"expiry_date": ["有效期不能早于生产日期。"]}
            )
        return attrs

    def create_for_user(self, user):
        medicine, _ = MedicineItem.objects.get_or_create(
            owner=user,
            name=self.validated_data["medicine_name"].strip(),
            specification=self.validated_data.get("specification", "").strip(),
        )
        batch = InventoryBatch(
            medicine=medicine,
            batch_number=self.validated_data.get("batch_number", "").strip(),
            production_date=self.validated_data.get("production_date"),
            expiry_date=self.validated_data.get("expiry_date"),
            quantity=self.validated_data.get("quantity", 1),
        )
        batch.full_clean()
        batch.save()
        return batch


class MedicineDescriptionParseSerializer(serializers.Serializer):
    text = serializers.CharField(
        max_length=500,
        trim_whitespace=True,
        allow_blank=False,
    )


class InventoryBatchSerializer(serializers.ModelSerializer):
    medicine_name = serializers.CharField(source="medicine.name")
    specification = serializers.CharField(source="medicine.specification")
    opened_use_before = serializers.SerializerMethodField()
    effective_deadline = serializers.SerializerMethodField()
    expiry_status = serializers.SerializerMethodField()
    days_until_expiry = serializers.SerializerMethodField()

    class Meta:
        model = InventoryBatch
        fields = (
            "id",
            "medicine_id",
            "medicine_name",
            "specification",
            "batch_number",
            "production_date",
            "expiry_date",
            "opened_at",
            "opened_shelf_life_days",
            "opened_use_before",
            "effective_deadline",
            "quantity",
            "expiry_status",
            "days_until_expiry",
        )

    @cached_property
    def today(self):
        return timezone.localdate(timezone=ZoneInfo("Asia/Shanghai"))

    def get_expiry_status(self, batch):
        deadline = batch.effective_deadline
        if deadline is None:
            return "unknown"
        today = self.today
        if deadline < today:
            return "expired"
        if deadline <= today + timedelta(days=30):
            return "expiring_soon"
        return "valid"

    def get_days_until_expiry(self, batch):
        deadline = batch.effective_deadline
        if deadline is None:
            return None
        return (deadline - self.today).days

    def get_opened_use_before(self, batch):
        return batch.opened_use_before

    def get_effective_deadline(self, batch):
        return batch.effective_deadline

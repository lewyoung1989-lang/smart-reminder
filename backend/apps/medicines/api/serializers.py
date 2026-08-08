from datetime import timedelta
from functools import cached_property
from zoneinfo import ZoneInfo

from django.utils import timezone
from rest_framework import serializers

from apps.medicines.models import ExpiryBatchAction, InventoryBatch


class ExpiryBatchActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=ExpiryBatchAction.Action.choices)


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

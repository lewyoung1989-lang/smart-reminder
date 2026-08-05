from datetime import timedelta
from functools import cached_property
from zoneinfo import ZoneInfo

from django.utils import timezone
from rest_framework import serializers

from apps.medicines.models import InventoryBatch


class InventoryBatchSerializer(serializers.ModelSerializer):
    medicine_name = serializers.CharField(source="medicine.name")
    specification = serializers.CharField(source="medicine.specification")
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
            "quantity",
            "expiry_status",
            "days_until_expiry",
        )

    @cached_property
    def today(self):
        return timezone.localdate(timezone=ZoneInfo("Asia/Shanghai"))

    def get_expiry_status(self, batch):
        expiry_date = batch.expiry_date
        if expiry_date is None:
            return "unknown"
        today = self.today
        if expiry_date < today:
            return "expired"
        if expiry_date <= today + timedelta(days=30):
            return "expiring_soon"
        return "valid"

    def get_days_until_expiry(self, batch):
        if batch.expiry_date is None:
            return None
        return (batch.expiry_date - self.today).days

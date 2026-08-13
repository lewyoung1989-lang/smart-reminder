from datetime import timedelta
from functools import cached_property
from zoneinfo import ZoneInfo

from django.utils import timezone
from rest_framework import serializers

from apps.medicines.models import ExpiryBatchAction, InventoryBatch, MedicineItem
from apps.medicines.services.photos import (
    delete_replaced_photo_after_commit,
    photo_content_type,
    validate_medicine_photo_key,
)
from apps.ocr.providers.storage import get_object_storage


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
    scope = serializers.ChoiceField(
        choices=("personal", "family"), required=False, default="personal"
    )
    medicine_name = serializers.CharField(max_length=200, trim_whitespace=True)
    specification = serializers.CharField(
        max_length=120,
        required=False,
        allow_blank=True,
        trim_whitespace=True,
    )
    manufacturer = serializers.CharField(
        max_length=200,
        required=False,
        allow_blank=True,
        trim_whitespace=True,
    )
    photo_object_key = serializers.CharField(
        max_length=300,
        required=False,
        allow_blank=True,
        trim_whitespace=True,
        write_only=True,
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
        from apps.families.services import record_event
        from apps.medicines.services.access import resolve_inventory_scope

        ownership = resolve_inventory_scope(user, self.validated_data["scope"])
        manufacturer = self.validated_data.get("manufacturer", "").strip()
        photo_object_key = self.validated_data.get("photo_object_key", "").strip()
        if photo_object_key:
            try:
                validate_medicine_photo_key(user=user, object_key=photo_object_key)
            except ValueError as error:
                raise serializers.ValidationError(
                    {"photo_object_key": "照片不属于当前用户。"}
                ) from error
        medicine, created = MedicineItem.objects.get_or_create(
            **ownership,
            name=self.validated_data["medicine_name"].strip(),
            specification=self.validated_data.get("specification", "").strip(),
            defaults={
                "manufacturer": manufacturer,
                "photo_object_key": photo_object_key,
                "photo_content_type": (
                    photo_content_type(photo_object_key) if photo_object_key else ""
                ),
            },
        )
        if not created:
            changed_fields = []
            if manufacturer and not medicine.manufacturer:
                medicine.manufacturer = manufacturer
                changed_fields.append("manufacturer")
            if photo_object_key:
                replaced_photo_object_key = medicine.photo_object_key
                medicine.photo_object_key = photo_object_key
                medicine.photo_content_type = photo_content_type(photo_object_key)
                changed_fields.extend(["photo_object_key", "photo_content_type"])
                if replaced_photo_object_key != photo_object_key:
                    delete_replaced_photo_after_commit(replaced_photo_object_key)
            if changed_fields:
                medicine.save(update_fields=changed_fields)
        batch = InventoryBatch(
            medicine=medicine,
            batch_number=self.validated_data.get("batch_number", "").strip(),
            production_date=self.validated_data.get("production_date"),
            expiry_date=self.validated_data.get("expiry_date"),
            quantity=self.validated_data.get("quantity", 1),
            created_by=user,
            updated_by=user,
        )
        batch.full_clean()
        batch.save()
        if medicine.family_id:
            record_event(
                family=medicine.family,
                actor=user,
                event_type="inventory_created",
                payload={"batch_id": str(batch.id)},
            )
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
    manufacturer = serializers.CharField(source="medicine.manufacturer")
    photo_url = serializers.SerializerMethodField()
    opened_use_before = serializers.SerializerMethodField()
    effective_deadline = serializers.SerializerMethodField()
    expiry_status = serializers.SerializerMethodField()
    days_until_expiry = serializers.SerializerMethodField()
    scope = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()

    class Meta:
        model = InventoryBatch
        fields = (
            "id",
            "medicine_id",
            "medicine_name",
            "specification",
            "manufacturer",
            "photo_url",
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
            "scope",
            "can_delete",
            "version",
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

    def get_photo_url(self, batch):
        key = batch.medicine.photo_object_key
        if not key:
            return None
        storage = self.context.get("object_storage")
        if storage is None:
            storage = get_object_storage()
        return storage.presign_get(key=key, expires_in=3600)

    def get_scope(self, batch):
        return "family" if batch.medicine.family_id else "personal"

    def get_can_delete(self, batch):
        request = self.context.get("request")
        if request is None:
            return batch.medicine.family_id is None
        if batch.medicine.owner_id == request.user.id:
            return True
        membership = getattr(request.user, "family_membership", None)
        return bool(
            membership
            and membership.family_id == batch.medicine.family_id
            and membership.role == "admin"
        )


class MedicinePhotoUploadSerializer(serializers.Serializer):
    content_type = serializers.ChoiceField(choices=["image/jpeg", "image/png"])
    byte_length = serializers.IntegerField(min_value=1)

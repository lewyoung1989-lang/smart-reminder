import uuid
from decimal import Decimal
from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class MedicineItem(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True
    )
    family = models.ForeignKey(
        "families.Family",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="medicines",
    )
    name = models.CharField(max_length=200)
    specification = models.CharField(max_length=120, blank=True)
    manufacturer = models.CharField(max_length=200, blank=True)
    photo_object_key = models.CharField(max_length=300, blank=True)
    photo_content_type = models.CharField(max_length=32, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["owner", "name", "specification"],
                name="unique_owner_medicine_specification",
                condition=models.Q(owner__isnull=False),
            ),
            models.UniqueConstraint(
                fields=["family", "name", "specification"],
                name="unique_family_medicine_specification",
                condition=models.Q(family__isnull=False),
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(owner__isnull=False, family__isnull=True)
                    | models.Q(owner__isnull=True, family__isnull=False)
                ),
                name="medicine_exactly_one_owner",
            ),
        ]


class InventoryBatch(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    medicine = models.ForeignKey(
        MedicineItem,
        on_delete=models.CASCADE,
        related_name="batches",
    )
    batch_number = models.CharField(max_length=100, blank=True)
    production_date = models.DateField(null=True, blank=True)
    expiry_date = models.DateField(null=True, blank=True)
    opened_at = models.DateField(null=True, blank=True)
    opened_shelf_life_days = models.PositiveIntegerField(null=True, blank=True)
    quantity = models.PositiveIntegerField(default=1)
    package_unit = models.CharField(max_length=16, blank=True)
    units_per_package = models.DecimalField(
        max_digits=10,
        decimal_places=3,
        null=True,
        blank=True,
    )
    unit_name = models.CharField(max_length=16, blank=True)
    loose_units = models.DecimalField(
        max_digits=12,
        decimal_places=3,
        default=Decimal("0"),
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_inventory_batches",
    )
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="updated_inventory_batches",
    )
    version = models.PositiveIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=(
                    models.Q(opened_at__isnull=True, opened_shelf_life_days__isnull=True)
                    | models.Q(opened_at__isnull=False, opened_shelf_life_days__gt=0)
                ),
                name="inventory_batch_opened_lifetime_consistent",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        package_unit="",
                        units_per_package__isnull=True,
                        unit_name="",
                        loose_units=0,
                    )
                    | (
                        ~models.Q(package_unit="")
                        & models.Q(units_per_package__gt=0)
                        & ~models.Q(unit_name="")
                        & models.Q(loose_units__gte=0)
                    )
                ),
                name="inventory_batch_precision_fields_consistent",
            ),
        ]

    def clean(self):
        super().clean()
        errors = {}
        if (self.opened_at is None) != (self.opened_shelf_life_days is None):
            errors["opened_shelf_life_days"] = "开封日期和开封后可用天数必须同时填写。"
        precision_values = (
            bool(self.package_unit),
            self.units_per_package is not None,
            bool(self.unit_name),
        )
        if any(precision_values) and not all(precision_values):
            errors["units_per_package"] = "包装单位、每包装含量和计量单位必须同时填写。"
        if self.units_per_package is not None:
            if self.units_per_package <= 0:
                errors["units_per_package"] = "每包装含量必须大于 0。"
            elif self.loose_units >= self.units_per_package:
                errors["loose_units"] = "已开封剩余量必须小于每包装含量。"
        elif self.loose_units != 0:
            errors["loose_units"] = "填写已开封剩余量前需要先填写精确包装信息。"
        if errors:
            raise ValidationError(errors)

    @property
    def opened_use_before(self):
        if self.opened_at is None or self.opened_shelf_life_days is None:
            return None
        return self.opened_at + timedelta(days=self.opened_shelf_life_days)

    @property
    def effective_deadline(self):
        candidates = [
            value for value in (self.expiry_date, self.opened_use_before) if value is not None
        ]
        return min(candidates) if candidates else None

    @property
    def total_remaining_units(self):
        if self.units_per_package is None or not self.unit_name:
            return None
        return self.units_per_package * self.quantity + self.loose_units


class ExpiryAlertState(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        ACTIVE = "active", "Active"
        COVERED = "covered", "Covered"
        RESOLVED = "resolved", "Resolved"
        SUPERSEDED = "superseded", "Superseded"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    batch = models.ForeignKey(
        InventoryBatch,
        on_delete=models.CASCADE,
        related_name="expiry_alerts",
    )
    threshold_days = models.PositiveIntegerField()
    deadline = models.DateField()
    status = models.CharField(max_length=16, choices=Status, default=Status.PENDING)
    activated_at = models.DateTimeField(null=True, blank=True)
    covered_at = models.DateTimeField(null=True, blank=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["batch", "threshold_days", "deadline"],
                name="expiry_alert_state_batch_threshold_deadline_unique",
            ),
        ]


class ExpiryBatchAction(models.Model):
    class Action(models.TextChoices):
        HANDLED = "handled", "Handled"
        USED_UP = "used_up", "Used up"
        CORRECTED = "corrected", "Corrected"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    batch = models.ForeignKey(
        InventoryBatch,
        on_delete=models.CASCADE,
        related_name="expiry_actions",
    )
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    action = models.CharField(max_length=16, choices=Action)
    change_json = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

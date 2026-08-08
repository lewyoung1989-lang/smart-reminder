import uuid
from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class MedicineItem(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    name = models.CharField(max_length=200)
    specification = models.CharField(max_length=120, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["owner", "name", "specification"],
                name="unique_owner_medicine_specification",
            )
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
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=(
                    models.Q(opened_at__isnull=True, opened_shelf_life_days__isnull=True)
                    | models.Q(opened_at__isnull=False, opened_shelf_life_days__gt=0)
                ),
                name="inventory_batch_opened_lifetime_consistent",
            ),
        ]

    def clean(self):
        super().clean()
        if (self.opened_at is None) != (self.opened_shelf_life_days is None):
            raise ValidationError(
                {"opened_shelf_life_days": "开封日期和开封后可用天数必须同时填写。"}
            )

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

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    batch = models.ForeignKey(
        InventoryBatch,
        on_delete=models.CASCADE,
        related_name="expiry_actions",
    )
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    action = models.CharField(max_length=16, choices=Action)
    created_at = models.DateTimeField(auto_now_add=True)

import re
import uuid
from decimal import Decimal
from datetime import timezone as datetime_timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


TIME_PATTERN = re.compile(r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")


class MedicationPlan(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    medicine = models.ForeignKey(
        "medicines.MedicineItem",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="medication_plans",
    )
    medicine_name = models.CharField(max_length=200, blank=True)
    source_workflow_draft = models.OneToOneField(
        "workflows.WorkflowDraft",
        on_delete=models.PROTECT,
        related_name="medication_plan",
        null=True,
        blank=True,
    )
    dosage_text = models.CharField(max_length=200)
    dose_quantity = models.DecimalField(
        max_digits=10,
        decimal_places=3,
        null=True,
        blank=True,
    )
    dose_unit = models.CharField(max_length=16, blank=True)
    auto_deduct_inventory = models.BooleanField(default=True)
    timezone = models.CharField(max_length=64)
    schedule_json = models.JSONField()
    enabled = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=~models.Q(dosage_text=""),
                name="medication_plan_dosage_text_nonempty",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(dose_quantity__isnull=True, dose_unit="")
                    | (models.Q(dose_quantity__gt=0) & ~models.Q(dose_unit=""))
                ),
                name="medication_plan_structured_dose_consistent",
            ),
        ]

    def clean(self):
        super().clean()
        errors = {}
        if self.medicine_id and self.owner_id:
            is_personal = self.medicine.owner_id == self.owner_id
            is_family = (
                self.medicine.family_id is not None
                and self.medicine.family.members.filter(user_id=self.owner_id).exists()
            )
            if not is_personal and not is_family:
                errors["medicine"] = "The medicine must be available to the plan owner."
        if (self.dose_quantity is None) != (self.dose_unit == ""):
            errors["dose_quantity"] = "剂量数值和计量单位必须同时填写。"
        elif self.dose_quantity is not None and self.dose_quantity <= 0:
            errors["dose_quantity"] = "每次剂量必须大于 0。"
        try:
            ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError):
            errors["timezone"] = "Enter a valid IANA timezone."
        times = self.schedule_json.get("times") if isinstance(self.schedule_json, dict) else None
        if (
            not isinstance(times, list)
            or not times
            or any(not isinstance(value, str) or not TIME_PATTERN.fullmatch(value) for value in times)
            or len(times) != len(set(times))
        ):
            errors["schedule_json"] = "times must be a non-empty list of unique HH:MM values."
        if errors:
            raise ValidationError(errors)


class MedicationOccurrence(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        TAKEN = "taken", "Taken"
        SKIPPED = "skipped", "Skipped"
        MISSED = "missed", "Missed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    plan = models.ForeignKey(
        MedicationPlan,
        on_delete=models.CASCADE,
        related_name="occurrences",
    )
    scheduled_at = models.DateTimeField(db_index=True)
    index = models.PositiveIntegerField()
    status = models.CharField(max_length=16, choices=Status, default=Status.PENDING)
    acted_at = models.DateTimeField(null=True, blank=True)
    idempotency_key = models.CharField(max_length=128, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["plan", "index"],
                name="medication_occurrence_plan_index_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=["pending", "taken", "skipped", "missed"]),
                name="medication_occurrence_status_valid",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(status="pending", acted_at__isnull=True)
                    | models.Q(status__in=["taken", "skipped", "missed"], acted_at__isnull=False)
                ),
                name="medication_occurrence_action_consistent",
            ),
            models.CheckConstraint(
                condition=~models.Q(idempotency_key=""),
                name="medication_occurrence_idempotency_key_nonempty",
            ),
        ]

    def clean(self):
        super().clean()
        errors = {}
        if self.scheduled_at and self.scheduled_at.tzinfo != datetime_timezone.utc:
            errors["scheduled_at"] = "scheduled_at must be expressed in UTC."
        is_pending = self.status == self.Status.PENDING
        if is_pending == (self.acted_at is not None):
            errors["acted_at"] = (
                "pending occurrences must not be acted on; terminal occurrences require acted_at."
            )
        if errors:
            raise ValidationError(errors)


class IntakeEvent(models.Model):
    class Action(models.TextChoices):
        TAKEN = "taken", "Taken"
        SKIPPED = "skipped", "Skipped"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    occurrence = models.OneToOneField(
        MedicationOccurrence,
        on_delete=models.CASCADE,
        related_name="intake_event",
    )
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    action = models.CharField(max_length=16, choices=Action)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=models.Q(action__in=["taken", "skipped"]),
                name="medication_intake_event_action_valid",
            ),
        ]

    def clean(self):
        super().clean()
        errors = {}
        if self.occurrence_id:
            if self.user_id and self.occurrence.plan.owner_id != self.user_id:
                errors["user"] = "The intake event user must own the medication plan."
            if self.action != self.occurrence.status:
                errors["action"] = "The intake event action must match the occurrence status."
        if errors:
            raise ValidationError(errors)


class InventoryDeductionAttempt(models.Model):
    class Status(models.TextChoices):
        DEDUCTED = "deducted", "Deducted"
        DISABLED = "disabled", "Disabled"
        MEDICINE_UNLINKED = "medicine_unlinked", "Medicine unlinked"
        NOT_CONFIGURED = "not_configured", "Inventory not configured"
        UNIT_MISMATCH = "unit_mismatch", "Unit mismatch"
        INSUFFICIENT = "insufficient", "Insufficient inventory"
        ACCESS_DENIED = "access_denied", "Access denied"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    intake_event = models.OneToOneField(
        IntakeEvent,
        on_delete=models.CASCADE,
        related_name="inventory_deduction_attempt",
    )
    status = models.CharField(max_length=32, choices=Status)
    requested_quantity = models.DecimalField(
        max_digits=10,
        decimal_places=3,
        null=True,
        blank=True,
    )
    deducted_quantity = models.DecimalField(
        max_digits=10,
        decimal_places=3,
        default=Decimal("0"),
    )
    unit_name = models.CharField(max_length=16, blank=True)
    remaining_quantity = models.DecimalField(
        max_digits=12,
        decimal_places=3,
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)


class InventoryDeductionEntry(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    attempt = models.ForeignKey(
        InventoryDeductionAttempt,
        on_delete=models.CASCADE,
        related_name="entries",
    )
    batch = models.ForeignKey(
        "medicines.InventoryBatch",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="medication_deductions",
    )
    quantity = models.DecimalField(max_digits=10, decimal_places=3)
    before_quantity = models.DecimalField(max_digits=12, decimal_places=3)
    after_quantity = models.DecimalField(max_digits=12, decimal_places=3)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["attempt", "batch"],
                name="inventory_deduction_attempt_batch_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(quantity__gt=0),
                name="inventory_deduction_entry_quantity_positive",
            ),
        ]

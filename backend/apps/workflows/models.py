import uuid

from django.conf import settings
from django.core.validators import RegexValidator
from django.db import models
from django.db.models.functions import Length
from django.db.models.lookups import Exact


SHA256_HEX_PATTERN = r"^[0-9a-f]{64}$"
sha256_hex_validator = RegexValidator(
    regex=SHA256_HEX_PATTERN,
    message="Enter a 64-character lowercase SHA-256 hexadecimal value.",
)


class WorkflowTemplate(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        DEPRECATED = "deprecated", "Deprecated"
        RETIRED = "retired", "Retired"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    template_key = models.CharField(max_length=128)
    version = models.CharField(max_length=32)
    status = models.CharField(max_length=32, choices=Status, default=Status.ACTIVE)
    capabilities_json = models.JSONField(default=list)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["template_key", "version"],
                name="workflow_template_key_version_unique",
            ),
        ]


class TrustGrant(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        REVOKED = "revoked", "Revoked"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    capability_signature = models.CharField(
        max_length=64,
        validators=[sha256_hex_validator],
    )
    template_key = models.CharField(max_length=128)
    template_major_version = models.PositiveIntegerField()
    scope_json = models.JSONField(default=dict)
    status = models.CharField(max_length=32, choices=Status, default=Status.ACTIVE)
    expires_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=[
                    "user",
                    "capability_signature",
                    "template_key",
                    "template_major_version",
                ],
                condition=models.Q(status="active"),
                name="workflow_active_grant_unique",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(capability_signature__regex=SHA256_HEX_PATTERN)
                    & Exact(Length("capability_signature"), 64)
                ),
                name="workflow_grant_signature_sha256_valid",
            ),
        ]


class WorkflowDraft(models.Model):
    class Status(models.TextChoices):
        PENDING_CONFIRMATION = "pending_confirmation", "Pending confirmation"
        CONFIRMED = "confirmed", "Confirmed"
        EXPIRED = "expired", "Expired"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    task_spec_json = models.JSONField()
    workflow_spec_json = models.JSONField()
    policy_json = models.JSONField()
    status = models.CharField(
        max_length=32,
        choices=Status,
        default=Status.PENDING_CONFIRMATION,
    )
    expires_at = models.DateTimeField()
    confirmed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class WorkflowRun(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        RUNNING = "running", "Running"
        SUCCEEDED = "succeeded", "Succeeded"
        FAILED = "failed", "Failed"
        CANCELLED = "cancelled", "Cancelled"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    workflow = models.ForeignKey(
        "reminders.ReminderRule",
        on_delete=models.CASCADE,
        related_name="workflow_runs",
    )
    idempotency_key = models.CharField(max_length=128)
    status = models.CharField(max_length=32, choices=Status, default=Status.PENDING)
    scheduled_for = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    finished_at = models.DateTimeField(null=True, blank=True)
    result_json = models.JSONField(default=dict)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["workflow", "idempotency_key"],
                name="workflow_run_idempotency_unique",
            ),
        ]

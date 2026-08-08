import uuid

from django.conf import settings
from django.db import models


class VoiceParseSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    transcript_sha256 = models.CharField(max_length=64)
    parser_source = models.CharField(max_length=32, default="local")
    status = models.CharField(max_length=32, default="parsed")
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)


class ReminderDraft(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.OneToOneField(VoiceParseSession, on_delete=models.CASCADE)
    draft_json = models.JSONField()
    ambiguities_json = models.JSONField(default=list)
    status = models.CharField(max_length=32, default="pending_confirmation")
    expires_at = models.DateTimeField()
    confirmed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class ReminderRule(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    title = models.CharField(max_length=200)
    timezone = models.CharField(max_length=64)
    schedule_json = models.JSONField()
    conditions_json = models.JSONField(default=dict)
    severity = models.CharField(max_length=32)
    scheduled_at = models.DateTimeField(db_index=True, null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    enabled = models.BooleanField(default=True)
    template_key = models.CharField(max_length=128, null=True, blank=True)
    template_version = models.CharField(max_length=32, null=True, blank=True)
    schema_version = models.PositiveIntegerField(null=True, blank=True)
    workflow_spec_json = models.JSONField(null=True, blank=True)
    next_run_at = models.DateTimeField(null=True, blank=True)
    last_run_at = models.DateTimeField(null=True, blank=True)
    revision = models.PositiveIntegerField(default=1, null=True, blank=True)
    paused_reason = models.CharField(max_length=128, null=True, blank=True)
    source_draft = models.OneToOneField(
        ReminderDraft,
        on_delete=models.PROTECT,
        related_name="confirmed_rule",
        null=True,
        blank=True,
    )
    workflow_draft = models.OneToOneField(
        "workflows.WorkflowDraft",
        on_delete=models.PROTECT,
        related_name="confirmed_rule",
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)

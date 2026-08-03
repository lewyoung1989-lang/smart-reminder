import uuid

from django.conf import settings
from django.db import models


class VoiceParseSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    transcript_sha256 = models.CharField(max_length=64)
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
    enabled = models.BooleanField(default=True)
    source_draft = models.OneToOneField(
        ReminderDraft,
        on_delete=models.PROTECT,
        related_name="confirmed_rule",
    )
    created_at = models.DateTimeField(auto_now_add=True)

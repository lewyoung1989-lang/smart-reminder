import uuid

from django.conf import settings
from django.db import models


class Family(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=40, default="我的家庭")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class FamilyMember(models.Model):
    class Role(models.TextChoices):
        ADMIN = "admin", "管理员"
        MEMBER = "member", "普通成员"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(Family, on_delete=models.CASCADE, related_name="members")
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="family_membership",
    )
    role = models.CharField(max_length=12, choices=Role, default=Role.MEMBER)
    nickname = models.CharField(max_length=30)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["family", "user"], name="unique_family_member"
            )
        ]


class FamilyInvitation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        Family, on_delete=models.CASCADE, related_name="invitations"
    )
    code = models.CharField(max_length=6, unique=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="created_family_invitations",
    )
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    used_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="used_family_invitations",
    )
    created_at = models.DateTimeField(auto_now_add=True)


class FamilyAuditEvent(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(Family, on_delete=models.CASCADE, related_name="audit_events")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    event_type = models.CharField(max_length=40)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

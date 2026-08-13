import secrets
import string
from datetime import timedelta

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from .models import Family, FamilyAuditEvent, FamilyInvitation, FamilyMember


MAX_FAMILY_MEMBERS = 10
INVITATION_LIFETIME = timedelta(hours=24)


def membership_for(user, *, lock=False):
    queryset = FamilyMember.objects.select_related("family")
    if lock:
        queryset = queryset.select_for_update()
    return queryset.filter(user=user).first()


def require_membership(user, *, admin=False, lock=False):
    membership = membership_for(user, lock=lock)
    if membership is None:
        raise ValidationError({"code": "family_membership_required"})
    if admin and membership.role != FamilyMember.Role.ADMIN:
        raise PermissionDenied("仅家庭管理员可执行此操作。")
    return membership


def record_event(*, family, actor, event_type, payload=None):
    return FamilyAuditEvent.objects.create(
        family=family,
        actor=actor,
        event_type=event_type,
        payload=payload or {},
    )


def create_invitation(*, user):
    membership = require_membership(user, admin=True)
    alphabet = string.digits
    for _ in range(20):
        code = "".join(secrets.choice(alphabet) for _ in range(6))
        try:
            invitation = FamilyInvitation.objects.create(
                family=membership.family,
                code=code,
                created_by=user,
                expires_at=timezone.now() + INVITATION_LIFETIME,
            )
        except IntegrityError:
            continue
        record_event(
            family=membership.family,
            actor=user,
            event_type="invitation_created",
        )
        return invitation
    raise ValidationError({"code": "invitation_generation_failed"})


@transaction.atomic
def join_family(*, user, code, nickname):
    if membership_for(user, lock=True) is not None:
        raise ValidationError({"code": "already_in_family"})
    invitation = (
        FamilyInvitation.objects.select_for_update()
        .select_related("family")
        .filter(code=code)
        .first()
    )
    now = timezone.now()
    if invitation is None or invitation.used_at is not None or invitation.expires_at <= now:
        raise ValidationError({"code": "invalid_or_expired_invitation"})
    family = Family.objects.select_for_update().get(id=invitation.family_id)
    if family.members.count() >= MAX_FAMILY_MEMBERS:
        raise ValidationError({"code": "family_member_limit_reached"})
    member = FamilyMember.objects.create(
        family=family,
        user=user,
        nickname=nickname,
    )
    invitation.used_at = now
    invitation.used_by = user
    invitation.save(update_fields=["used_at", "used_by"])
    record_event(
        family=family,
        actor=user,
        event_type="member_joined",
        payload={"member_id": str(member.id)},
    )
    return member

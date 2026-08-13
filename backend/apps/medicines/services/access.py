from django.db.models import Q
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.families.models import FamilyMember


def family_membership(user):
    return FamilyMember.objects.select_related("family").filter(user=user).first()


def medicine_access_query(user):
    return Q(owner=user) | Q(family__members__user=user)


def inventory_access_query(user):
    return Q(medicine__owner=user) | Q(medicine__family__members__user=user)


def resolve_inventory_scope(user, scope):
    if scope == "personal":
        return {"owner": user, "family": None}
    if scope != "family":
        raise ValidationError({"scope": "药箱范围必须是 personal 或 family。"})
    membership = family_membership(user)
    if membership is None:
        raise ValidationError({"scope": "当前账号尚未加入家庭。"})
    return {"owner": None, "family": membership.family}


def require_batch_access(batch, user, *, delete=False):
    if batch.medicine.owner_id == user.id:
        return
    membership = family_membership(user)
    if membership is None or membership.family_id != batch.medicine.family_id:
        raise PermissionDenied("无权访问该库存。")
    if delete and membership.role != FamilyMember.Role.ADMIN:
        raise PermissionDenied("仅家庭管理员可删除共享库存。")

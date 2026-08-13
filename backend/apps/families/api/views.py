from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.phone import mask_phone
from apps.families.models import Family, FamilyMember
from apps.families.services import (
    create_invitation,
    join_family,
    membership_for,
    record_event,
    require_membership,
)
from apps.medication.models import MedicationPlan
from apps.ocr.providers.storage import get_object_storage

from .serializers import (
    CreateFamilySerializer,
    JoinFamilySerializer,
    TransferAdminSerializer,
    UpdateFamilySerializer,
    UpdateNicknameSerializer,
)


def _member_payload(member):
    phone = getattr(getattr(member.user, "phone_identity", None), "phone_e164", "")
    return {
        "id": str(member.id),
        "nickname": member.nickname,
        "phone_masked": mask_phone(phone) if phone else "未绑定手机号",
        "role": member.role,
        "is_self": False,
        "joined_at": member.joined_at.isoformat(),
    }


def _family_payload(membership):
    members = membership.family.members.select_related("user__phone_identity").order_by(
        "joined_at", "id"
    )
    payload = [_member_payload(member) for member in members]
    for item, member in zip(payload, members):
        item["is_self"] = member.id == membership.id
    return {
        "id": str(membership.family_id),
        "name": membership.family.name,
        "role": membership.role,
        "members": payload,
    }


class CurrentFamilyView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        membership = membership_for(request.user)
        return Response({"family": _family_payload(membership) if membership else None})

    def post(self, request):
        serializer = CreateFamilySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if membership_for(request.user) is not None:
            raise ValidationError({"code": "already_in_family"})
        with transaction.atomic():
            family = Family.objects.create(name=serializer.validated_data["name"])
            member = FamilyMember.objects.create(
                family=family,
                user=request.user,
                role=FamilyMember.Role.ADMIN,
                nickname=serializer.validated_data["nickname"],
            )
            record_event(family=family, actor=request.user, event_type="family_created")
        return Response(_family_payload(member), status=status.HTTP_201_CREATED)

    def patch(self, request):
        membership = require_membership(request.user, admin=True)
        serializer = UpdateFamilySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        membership.family.name = serializer.validated_data["name"]
        membership.family.save(update_fields=["name", "updated_at"])
        record_event(family=membership.family, actor=request.user, event_type="family_renamed")
        return Response(_family_payload(membership))

    def delete(self, request):
        membership = require_membership(request.user, admin=True)
        if membership.family.members.count() != 1:
            raise ValidationError({"code": "family_not_empty"})
        family = membership.family
        photo_keys = list(
            family.medicines.exclude(photo_object_key="").values_list(
                "photo_object_key", flat=True
            )
        )
        MedicationPlan.objects.filter(medicine__family=family).update(
            enabled=False, updated_at=timezone.now()
        )
        family.delete()
        storage = get_object_storage()
        transaction.on_commit(lambda: _delete_photos(storage, photo_keys))
        return Response(status=status.HTTP_204_NO_CONTENT)


class FamilyInvitationView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        invitation = create_invitation(user=request.user)
        return Response(
            {"code": invitation.code, "expires_at": invitation.expires_at.isoformat()},
            status=status.HTTP_201_CREATED,
        )


class JoinFamilyView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = JoinFamilySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        member = join_family(user=request.user, **serializer.validated_data)
        return Response(_family_payload(member), status=status.HTTP_201_CREATED)


class FamilyMembershipView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request):
        membership = require_membership(request.user)
        serializer = UpdateNicknameSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        membership.nickname = serializer.validated_data["nickname"]
        membership.save(update_fields=["nickname"])
        return Response(_family_payload(membership))

    def delete(self, request):
        membership = require_membership(request.user)
        if membership.role == FamilyMember.Role.ADMIN:
            raise ValidationError({"code": "admin_must_transfer_or_disband"})
        family = membership.family
        MedicationPlan.objects.filter(
            owner=request.user, medicine__family=family, enabled=True
        ).update(enabled=False, updated_at=timezone.now())
        record_event(family=family, actor=request.user, event_type="member_left")
        membership.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class TransferFamilyAdminView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request):
        current = require_membership(request.user, admin=True, lock=True)
        serializer = TransferAdminSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        target = FamilyMember.objects.select_for_update().filter(
            id=serializer.validated_data["member_id"], family=current.family
        ).first()
        if target is None or target.id == current.id:
            raise ValidationError({"member_id": "请选择家庭内其他成员。"})
        current.role = FamilyMember.Role.MEMBER
        target.role = FamilyMember.Role.ADMIN
        current.save(update_fields=["role"])
        target.save(update_fields=["role"])
        record_event(
            family=current.family,
            actor=request.user,
            event_type="admin_transferred",
            payload={"member_id": str(target.id)},
        )
        return Response(_family_payload(current))


class FamilyMemberDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, member_id):
        current = require_membership(request.user, admin=True)
        target = FamilyMember.objects.filter(id=member_id, family=current.family).first()
        if target is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        if target.id == current.id:
            raise ValidationError({"code": "cannot_remove_self"})
        MedicationPlan.objects.filter(
            owner=target.user, medicine__family=current.family, enabled=True
        ).update(enabled=False, updated_at=timezone.now())
        record_event(
            family=current.family,
            actor=request.user,
            event_type="member_removed",
            payload={"member_id": str(target.id)},
        )
        target.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


def _delete_photos(storage, photo_keys):
    for key in photo_keys:
        try:
            storage.delete(key)
        except Exception:
            # 家庭数据已删除，存储清理失败交给运维巡检处理。
            pass

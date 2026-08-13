from datetime import timedelta

import pytest
from django.utils import timezone

from apps.accounts.models import PhoneIdentity
from apps.families.models import FamilyAuditEvent, FamilyMember
from apps.medication.models import MedicationPlan
from apps.medicines.models import InventoryBatch, MedicineItem


def create_phone_user(django_user_model, phone, suffix):
    user = django_user_model.objects.create_user(username=suffix)
    PhoneIdentity.objects.create(user=user, phone_e164=phone)
    return user


@pytest.mark.django_db
def test_create_invite_and_join_family(api_client, django_user_model):
    admin = create_phone_user(django_user_model, "+8613800000001", "family-admin")
    member = create_phone_user(django_user_model, "+8613800000002", "family-member")
    api_client.force_authenticate(admin)
    created = api_client.post(
        "/api/v1/families/current",
        {"name": "刘家药箱", "nickname": "爸爸"},
        format="json",
    )
    assert created.status_code == 201
    assert created.json()["role"] == "admin"

    invitation = api_client.post("/api/v1/families/invitations", {}, format="json")
    assert invitation.status_code == 201
    assert len(invitation.json()["code"]) == 6

    api_client.force_authenticate(member)
    joined = api_client.post(
        "/api/v1/families/join",
        {"code": invitation.json()["code"], "nickname": "妈妈"},
        format="json",
    )
    assert joined.status_code == 201
    assert [item["nickname"] for item in joined.json()["members"]] == ["爸爸", "妈妈"]
    assert joined.json()["members"][0]["phone_masked"] == "138****0001"
    assert FamilyAuditEvent.objects.filter(event_type="member_joined").exists()


@pytest.mark.django_db
def test_invitation_is_single_use_and_expires(api_client, django_user_model):
    admin = create_phone_user(django_user_model, "+8613800000011", "invite-admin")
    first = create_phone_user(django_user_model, "+8613800000012", "invite-first")
    second = create_phone_user(django_user_model, "+8613800000013", "invite-second")
    api_client.force_authenticate(admin)
    api_client.post(
        "/api/v1/families/current", {"nickname": "管理员"}, format="json"
    )
    code = api_client.post("/api/v1/families/invitations", {}, format="json").json()["code"]
    api_client.force_authenticate(first)
    assert api_client.post(
        "/api/v1/families/join", {"code": code, "nickname": "成员"}, format="json"
    ).status_code == 201
    api_client.force_authenticate(second)
    assert api_client.post(
        "/api/v1/families/join", {"code": code, "nickname": "另一成员"}, format="json"
    ).status_code == 400

    api_client.force_authenticate(admin)
    expired = api_client.post("/api/v1/families/invitations", {}, format="json").json()["code"]
    from apps.families.models import FamilyInvitation

    FamilyInvitation.objects.filter(code=expired).update(
        expires_at=timezone.now() - timedelta(seconds=1)
    )
    api_client.force_authenticate(second)
    assert api_client.post(
        "/api/v1/families/join", {"code": expired, "nickname": "另一成员"}, format="json"
    ).status_code == 400


@pytest.mark.django_db
def test_member_can_edit_but_only_admin_can_delete_family_inventory(
    api_client, django_user_model
):
    admin = create_phone_user(django_user_model, "+8613800000021", "stock-admin")
    member = create_phone_user(django_user_model, "+8613800000022", "stock-member")
    family = FamilyMember.objects.create(
        family_id=(
            api_client.force_authenticate(admin)
            or api_client.post(
                "/api/v1/families/current", {"nickname": "管理员"}, format="json"
            ).json()["id"]
        ),
        user=member,
        nickname="成员",
    ).family
    medicine = MedicineItem.objects.create(family=family, name="家庭药")
    batch = InventoryBatch.objects.create(medicine=medicine, expiry_date="2027-01-01")

    api_client.force_authenticate(member)
    listed = api_client.get("/api/v1/inventory-batches", {"scope": "family"})
    assert listed.status_code == 200
    assert listed.json()["results"][0]["can_delete"] is False
    corrected = api_client.patch(
        f"/api/v1/inventory-batches/{batch.id}/expiry-dates",
        {"expiry_date": "2027-02-01", "version": 1},
        format="json",
    )
    assert corrected.status_code == 200
    assert corrected.json()["version"] == 2
    assert FamilyAuditEvent.objects.filter(event_type="inventory_corrected").exists()
    assert api_client.delete(f"/api/v1/inventory-batches/{batch.id}").status_code == 403

    api_client.force_authenticate(admin)
    assert api_client.delete(f"/api/v1/inventory-batches/{batch.id}").status_code == 204


@pytest.mark.django_db
def test_leaving_family_pauses_private_plan_using_shared_medicine(
    api_client, django_user_model
):
    admin = create_phone_user(django_user_model, "+8613800000031", "leave-admin")
    member = create_phone_user(django_user_model, "+8613800000032", "leave-member")
    api_client.force_authenticate(admin)
    family_id = api_client.post(
        "/api/v1/families/current", {"nickname": "管理员"}, format="json"
    ).json()["id"]
    membership = FamilyMember.objects.create(
        family_id=family_id, user=member, nickname="成员"
    )
    medicine = MedicineItem.objects.create(family=membership.family, name="共享药")
    plan = MedicationPlan.objects.create(
        owner=member,
        medicine=medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    api_client.force_authenticate(member)
    assert api_client.delete("/api/v1/families/membership").status_code == 204
    plan.refresh_from_db()
    assert plan.enabled is False

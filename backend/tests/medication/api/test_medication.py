from datetime import datetime, timezone

import pytest
from rest_framework import status

from apps.medication.models import (
    IntakeEvent,
    InventoryDeductionAttempt,
    InventoryDeductionEntry,
    MedicationOccurrence,
    MedicationPlan,
)
from apps.medicines.models import InventoryBatch, LowStockAlertState, MedicineItem
from apps.workflows.models import WorkflowDraft


def create_confirmed_medication_draft(user):
    return WorkflowDraft.objects.create(
        user=user,
        task_spec_json={},
        workflow_spec_json={"template_key": "medication_cycle"},
        policy_json={},
        status=WorkflowDraft.Status.CONFIRMED,
        expires_at=datetime(2026, 8, 9, tzinfo=timezone.utc),
        confirmed_at=datetime(2026, 8, 8, tzinfo=timezone.utc),
    )


@pytest.mark.django_db
def test_create_plan_materializes_30_day_window(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    draft = create_confirmed_medication_draft(user)
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/medication/plans",
        {
            "workflow_draft_id": str(draft.id),
            "medicine_id": str(medicine.id),
            "dosage_text": "一次一片",
            "timezone": "Asia/Shanghai",
            "times": ["08:00", "20:30"],
        },
        format="json",
    )

    assert response.status_code == status.HTTP_201_CREATED
    assert response.data["medicine_id"] == str(medicine.id)
    assert response.data["dosage_text"] == "一次一片"
    assert MedicationOccurrence.objects.filter(plan_id=response.data["id"]).count() == 60


@pytest.mark.django_db
def test_create_plan_requires_confirmed_medication_workflow(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/medication/plans",
        {
            "medicine_id": str(medicine.id),
            "dosage_text": "一次一片",
            "timezone": "Asia/Shanghai",
            "times": ["08:00"],
        },
        format="json",
    )

    assert response.status_code == status.HTTP_400_BAD_REQUEST
    assert response.data == {"workflow_draft_id": ["需要已确认的周期用药工作流。"]}


@pytest.mark.django_db
def test_confirmed_medication_workflow_can_create_only_one_plan(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    draft = create_confirmed_medication_draft(user)
    payload = {
        "workflow_draft_id": str(draft.id),
        "medicine_id": str(medicine.id),
        "dosage_text": "一次一片",
        "timezone": "Asia/Shanghai",
        "times": ["08:00"],
    }
    api_client.force_authenticate(user)

    first = api_client.post("/api/v1/medication/plans", payload, format="json")
    second = api_client.post("/api/v1/medication/plans", payload, format="json")

    assert first.status_code == status.HTTP_201_CREATED
    assert second.status_code == status.HTTP_400_BAD_REQUEST
    assert MedicationPlan.objects.filter(source_workflow_draft=draft).count() == 1


@pytest.mark.django_db
def test_create_plan_does_not_disclose_another_users_medicine(
    api_client, user, django_user_model
):
    another = django_user_model.objects.create_user(username="other-medication-plan")
    medicine = MedicineItem.objects.create(owner=another, name="他人药品")
    draft = create_confirmed_medication_draft(user)
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/medication/plans",
        {
            "workflow_draft_id": str(draft.id),
            "medicine_id": str(medicine.id),
            "dosage_text": "一次一片",
            "timezone": "Asia/Shanghai",
            "times": ["08:00"],
        },
        format="json",
    )

    assert response.status_code == status.HTTP_400_BAD_REQUEST
    assert response.data == {"medicine_id": ["药品不存在或不属于当前用户。"]}
    assert MedicationOccurrence.objects.count() == 0


@pytest.mark.django_db
def test_mark_taken_is_idempotent_and_creates_one_event(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="维生素")
    draft = create_confirmed_medication_draft(user)
    api_client.force_authenticate(user)
    plan_response = api_client.post(
        "/api/v1/medication/plans",
        {
            "workflow_draft_id": str(draft.id),
            "medicine_id": str(medicine.id),
            "dosage_text": "一次一粒",
            "timezone": "Asia/Shanghai",
            "times": ["08:00"],
        },
        format="json",
    )
    occurrence = MedicationOccurrence.objects.filter(
        plan_id=plan_response.data["id"]
    ).earliest("scheduled_at")
    url = f"/api/v1/medication/occurrences/{occurrence.id}/actions"

    first = api_client.post(url, {"action": "taken"}, format="json")
    second = api_client.post(url, {"action": "taken"}, format="json")

    assert first.status_code == status.HTTP_200_OK
    assert second.status_code == status.HTTP_200_OK
    assert first.data["status"] == "taken"
    assert second.data == first.data
    assert IntakeEvent.objects.get(occurrence=occurrence).action == "taken"
    assert InventoryDeductionAttempt.objects.filter(
        intake_event__occurrence=occurrence
    ).count() == 1


@pytest.mark.django_db
def test_mark_taken_deducts_precise_inventory_once(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="维生素")
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        quantity=2,
        package_unit="瓶",
        units_per_package="10",
        unit_name="粒",
    )
    draft = create_confirmed_medication_draft(user)
    api_client.force_authenticate(user)
    plan_response = api_client.post(
        "/api/v1/medication/plans",
        {
            "workflow_draft_id": str(draft.id),
            "medicine_id": str(medicine.id),
            "dosage_text": "一次一粒",
            "timezone": "Asia/Shanghai",
            "times": ["08:00"],
        },
        format="json",
    )
    occurrence = MedicationOccurrence.objects.filter(
        plan_id=plan_response.data["id"]
    ).earliest("scheduled_at")
    url = f"/api/v1/medication/occurrences/{occurrence.id}/actions"

    first = api_client.post(url, {"action": "taken"}, format="json")
    second = api_client.post(url, {"action": "taken"}, format="json")

    assert first.status_code == status.HTTP_200_OK
    assert second.data == first.data
    assert first.data["inventory_deduction"] == {
        "status": "deducted",
        "deducted_quantity": "1",
        "unit": "粒",
        "remaining_quantity": "19",
        "message": "已记录服药，已扣减1粒，精确库存剩余19粒",
    }
    batch.refresh_from_db()
    assert batch.quantity == 1
    assert batch.loose_units == 9
    assert InventoryDeductionEntry.objects.count() == 1


@pytest.mark.django_db
def test_mark_taken_refreshes_low_stock_alerts(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="拜新同")
    InventoryBatch.objects.create(
        medicine=medicine,
        quantity=0,
        package_unit="盒",
        units_per_package="14",
        unit_name="片",
        loose_units="4",
    )
    draft = create_confirmed_medication_draft(user)
    api_client.force_authenticate(user)
    plan_response = api_client.post(
        "/api/v1/medication/plans",
        {
            "workflow_draft_id": str(draft.id),
            "medicine_id": str(medicine.id),
            "dosage_text": "一次一片",
            "timezone": "Asia/Shanghai",
            "times": ["08:00"],
        },
        format="json",
    )
    assert LowStockAlertState.objects.count() == 0
    occurrence = MedicationOccurrence.objects.filter(
        plan_id=plan_response.data["id"]
    ).earliest("scheduled_at")

    response = api_client.post(
        f"/api/v1/medication/occurrences/{occurrence.id}/actions",
        {"action": "taken"},
        format="json",
    )

    assert response.status_code == status.HTTP_200_OK
    alert = LowStockAlertState.objects.get(medicine=medicine)
    assert alert.status == LowStockAlertState.Status.ACTIVE
    assert alert.remaining_quantity == 3
    assert alert.days_remaining == 3


@pytest.mark.django_db
def test_mark_taken_uses_earliest_expiring_batch_first(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="降压药")
    later = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date="2027-01-01",
        quantity=1,
        package_unit="盒",
        units_per_package="7",
        unit_name="片",
    )
    earlier = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date="2026-12-01",
        quantity=1,
        package_unit="盒",
        units_per_package="7",
        unit_name="片",
        loose_units="1",
    )
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次两片",
        dose_quantity="2",
        dose_unit="片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    occurrence = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, tzinfo=timezone.utc),
        index=0,
        idempotency_key="earliest-expiry-first",
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/medication/occurrences/{occurrence.id}/actions",
        {"action": "taken"},
        format="json",
    )

    assert response.status_code == status.HTTP_200_OK
    earlier.refresh_from_db()
    later.refresh_from_db()
    assert earlier.quantity == 0
    assert earlier.loose_units == 6
    assert later.quantity == 1
    assert later.loose_units == 0


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("batch_kwargs", "expected_status"),
    [
        ({"quantity": 1}, "not_configured"),
        (
            {
                "quantity": 1,
                "package_unit": "盒",
                "units_per_package": "7",
                "unit_name": "粒",
            },
            "unit_mismatch",
        ),
        (
            {
                "quantity": 1,
                "package_unit": "盒",
                "units_per_package": "1",
                "unit_name": "片",
            },
            "insufficient",
        ),
    ],
)
def test_mark_taken_records_without_deducting_unsafe_inventory(
    api_client, user, batch_kwargs, expected_status
):
    medicine = MedicineItem.objects.create(owner=user, name="测试药")
    batch = InventoryBatch.objects.create(medicine=medicine, **batch_kwargs)
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次两片",
        dose_quantity="2",
        dose_unit="片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    occurrence = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, tzinfo=timezone.utc),
        index=0,
        idempotency_key=f"unsafe-{expected_status}",
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/medication/occurrences/{occurrence.id}/actions",
        {"action": "taken"},
        format="json",
    )

    assert response.status_code == status.HTTP_200_OK
    assert response.data["status"] == "taken"
    assert response.data["inventory_deduction"]["status"] == expected_status
    if expected_status == "not_configured":
        assert response.data["inventory_deduction"]["message"] == (
            "已记录服药，但测试药未记录每包装含量和剩余片数，无法自动扣减"
        )
    elif expected_status == "unit_mismatch":
        assert response.data["inventory_deduction"]["message"] == (
            "已记录服药，但测试药的药箱计量单位不是片，未自动扣减"
        )
    batch.refresh_from_db()
    assert batch.quantity == batch_kwargs["quantity"]
    assert batch.loose_units == 0
    assert InventoryDeductionEntry.objects.count() == 0


@pytest.mark.django_db
def test_skipped_occurrence_does_not_create_inventory_attempt(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="测试药")
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次一片",
        dose_quantity="1",
        dose_unit="片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    occurrence = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, tzinfo=timezone.utc),
        index=0,
        idempotency_key="skipped-no-deduction",
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/medication/occurrences/{occurrence.id}/actions",
        {"action": "skipped"},
        format="json",
    )

    assert response.status_code == status.HTTP_200_OK
    assert "inventory_deduction" not in response.data
    assert InventoryDeductionAttempt.objects.count() == 0


@pytest.mark.django_db
def test_occurrence_action_cannot_overwrite_existing_action(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="维生素")
    draft = create_confirmed_medication_draft(user)
    api_client.force_authenticate(user)
    plan_response = api_client.post(
        "/api/v1/medication/plans",
        {
            "workflow_draft_id": str(draft.id),
            "medicine_id": str(medicine.id),
            "dosage_text": "一次一粒",
            "timezone": "Asia/Shanghai",
            "times": ["08:00"],
        },
        format="json",
    )
    occurrence = MedicationOccurrence.objects.filter(
        plan_id=plan_response.data["id"]
    ).earliest("scheduled_at")
    url = f"/api/v1/medication/occurrences/{occurrence.id}/actions"

    api_client.post(url, {"action": "taken"}, format="json")
    response = api_client.post(url, {"action": "skipped"}, format="json")

    assert response.status_code == status.HTTP_409_CONFLICT
    assert response.data == {"code": "medication_occurrence_already_actioned"}
    occurrence.refresh_from_db()
    assert occurrence.status == "taken"


@pytest.mark.django_db
def test_occurrence_action_hides_another_users_occurrence(
    api_client, user, django_user_model
):
    another = django_user_model.objects.create_user(username="other-occurrence-user")
    medicine = MedicineItem.objects.create(owner=another, name="他人药品")
    plan = MedicationPlan.objects.create(
        owner=another,
        medicine=medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    occurrence = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, tzinfo=timezone.utc),
        index=0,
        idempotency_key="other-user-occurrence",
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/medication/occurrences/{occurrence.id}/actions",
        {"action": "taken"},
        format="json",
    )

    assert response.status_code == status.HTTP_404_NOT_FOUND
    occurrence.refresh_from_db()
    assert occurrence.status == "pending"


@pytest.mark.django_db
def test_occurrence_list_is_owner_scoped_and_orders_pending_items(api_client, user, django_user_model):
    another = django_user_model.objects.create_user(username="other-occurrence-list")
    own_medicine = MedicineItem.objects.create(owner=user, name="自己的药品")
    other_medicine = MedicineItem.objects.create(owner=another, name="他人的药品")
    own_plan = MedicationPlan.objects.create(
        owner=user,
        medicine=own_medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    other_plan = MedicationPlan.objects.create(
        owner=another,
        medicine=other_medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    first = MedicationOccurrence.objects.create(
        plan=own_plan,
        scheduled_at=datetime(2026, 8, 8, 0, tzinfo=timezone.utc),
        index=0,
        idempotency_key="own-list-first",
    )
    second = MedicationOccurrence.objects.create(
        plan=own_plan,
        scheduled_at=datetime(2026, 8, 9, 0, tzinfo=timezone.utc),
        index=1,
        idempotency_key="own-list-second",
    )
    MedicationOccurrence.objects.create(
        plan=other_plan,
        scheduled_at=datetime(2026, 8, 7, 0, tzinfo=timezone.utc),
        index=0,
        idempotency_key="other-user-list",
    )
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/medication/occurrences")

    assert response.status_code == status.HTTP_200_OK
    assert [item["id"] for item in response.data["results"]] == [str(first.id), str(second.id)]

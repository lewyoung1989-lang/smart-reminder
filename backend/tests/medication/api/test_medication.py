from datetime import datetime, timezone

import pytest
from rest_framework import status

from apps.medication.models import IntakeEvent, MedicationOccurrence, MedicationPlan
from apps.medicines.models import MedicineItem
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

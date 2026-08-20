from datetime import datetime, timezone

import pytest

from apps.medication.models import MedicationPlan
from apps.medication.services.workflow_plans import ensure_medication_plan_for_workflow
from apps.medicines.models import MedicineItem
from apps.workflows.domain.schemas import TaskSpec
from apps.workflows.models import WorkflowDraft


@pytest.mark.django_db
def test_workflow_plan_resolution_uses_explicit_medicine_id(user):
    named_candidate = MedicineItem.objects.create(owner=user, name="拜新同")
    selected = MedicineItem.objects.create(
        owner=user,
        name="拜新同",
        specification="用户选择的库存",
    )
    draft = WorkflowDraft.objects.create(
        user=user,
        source_text="每天八点吃拜新同一片",
        task_spec_json={},
        workflow_spec_json={},
        policy_json={},
        expires_at=datetime(2026, 8, 9, tzinfo=timezone.utc),
    )
    task = TaskSpec(
        title="用药提醒",
        template_hint="medication_cycle",
        slots={
            "medicine_name": named_candidate.name,
            "medicine_id": str(selected.id),
            "dose_text": "一次一片",
            "frequency": "daily",
            "time_of_day": "08:00",
        },
    )

    plan = ensure_medication_plan_for_workflow(
        draft=draft,
        task=task,
        now=datetime(2026, 8, 8, tzinfo=timezone.utc),
    )

    assert plan is not None
    assert plan.medicine == selected
    assert (
        MedicationPlan.objects.get(source_workflow_draft=draft).medicine
        == selected
    )

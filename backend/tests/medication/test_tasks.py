from datetime import datetime, timezone

import pytest
from django.conf import settings

from apps.medication.models import MedicationPlan
from apps.medicines.models import MedicineItem


def test_beat_materializes_medication_occurrences_daily():
    assert settings.CELERY_BEAT_SCHEDULE["materialize-medication-occurrences-daily"] == {
        "task": "apps.medication.tasks.materialize_medication_occurrences_task",
        "schedule": 86400.0,
    }


@pytest.mark.django_db
def test_materialization_task_maintains_enabled_plans(user):
    from apps.medication.tasks import materialize_medication_occurrences_task

    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    now = datetime(2026, 8, 8, 1, tzinfo=timezone.utc)

    created_plan_ids = materialize_medication_occurrences_task.run(now.isoformat())

    assert created_plan_ids == [str(plan.id)]
    assert plan.occurrences.count() == 30


@pytest.mark.django_db
def test_materialization_does_not_starve_later_enabled_plans(user):
    from apps.medication.services.occurrences import materialize_enabled_plans

    first_medicine = MedicineItem.objects.create(owner=user, name="药品一")
    second_medicine = MedicineItem.objects.create(owner=user, name="药品二")
    first = MedicationPlan.objects.create(
        owner=user,
        medicine=first_medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    second = MedicationPlan.objects.create(
        owner=user,
        medicine=second_medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )

    changed = materialize_enabled_plans(
        now=datetime(2026, 8, 8, 1, tzinfo=timezone.utc),
        batch_size=1,
    )

    assert {plan.id for plan in changed} == {first.id, second.id}

from datetime import datetime, timezone

import pytest

from apps.medication.models import MedicationPlan
from apps.medication.services.occurrences import materialize_occurrences
from apps.medicines.models import MedicineItem


@pytest.mark.django_db
def test_materialize_occurrences_creates_each_local_slot_once(user):
    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00", "20:30"]},
    )
    now = datetime(2026, 8, 8, 1, tzinfo=timezone.utc)

    first = materialize_occurrences(plan, now=now, days=2)
    second = materialize_occurrences(plan, now=now, days=2)

    assert len(first) == 4
    assert second == []
    assert list(plan.occurrences.order_by("scheduled_at").values_list("scheduled_at", flat=True)) == [
        datetime(2026, 8, 8, 0, tzinfo=timezone.utc),
        datetime(2026, 8, 8, 12, 30, tzinfo=timezone.utc),
        datetime(2026, 8, 9, 0, tzinfo=timezone.utc),
        datetime(2026, 8, 9, 12, 30, tzinfo=timezone.utc),
    ]


@pytest.mark.django_db
def test_materialize_occurrences_keeps_local_time_across_daylight_saving(user):
    medicine = MedicineItem.objects.create(owner=user, name="维生素")
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次一粒",
        timezone="America/New_York",
        schedule_json={"times": ["08:00"]},
    )

    materialize_occurrences(
        plan,
        now=datetime(2026, 3, 7, 12, tzinfo=timezone.utc),
        days=3,
    )

    assert list(plan.occurrences.order_by("scheduled_at").values_list("scheduled_at", flat=True)) == [
        datetime(2026, 3, 7, 13, tzinfo=timezone.utc),
        datetime(2026, 3, 8, 12, tzinfo=timezone.utc),
        datetime(2026, 3, 9, 12, tzinfo=timezone.utc),
    ]


@pytest.mark.django_db
def test_materialize_occurrences_skips_disabled_plan(user):
    medicine = MedicineItem.objects.create(owner=user, name="维生素")
    plan = MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次一粒",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
        enabled=False,
    )

    result = materialize_occurrences(
        plan,
        now=datetime(2026, 8, 8, 1, tzinfo=timezone.utc),
    )

    assert result == []
    assert not plan.occurrences.exists()

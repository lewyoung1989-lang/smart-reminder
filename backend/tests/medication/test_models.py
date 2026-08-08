from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction

from apps.medication.models import IntakeEvent, MedicationOccurrence, MedicationPlan
from apps.medicines.models import MedicineItem


def create_plan(user, *, medicine=None):
    medicine = medicine or MedicineItem.objects.create(owner=user, name="布洛芬")
    return MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00", "20:30"]},
    )


@pytest.mark.django_db
def test_medication_plan_belongs_to_the_same_owner_as_its_medicine(
    user, django_user_model
):
    another = django_user_model.objects.create_user(username="other-medication")
    other_medicine = MedicineItem.objects.create(owner=another, name="他人药品")
    plan = MedicationPlan(
        owner=user,
        medicine=other_medicine,
        dosage_text="一次一片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )

    with pytest.raises(ValidationError, match="medicine"):
        plan.full_clean()


@pytest.mark.django_db
@pytest.mark.parametrize(
    "schedule_json",
    [
        {},
        {"times": []},
        {"times": ["8:00"]},
        {"times": ["24:00"]},
        {"times": ["08:00", "08:00"]},
    ],
)
def test_medication_plan_requires_unique_hh_mm_schedule_times(user, schedule_json):
    medicine = MedicineItem.objects.create(owner=user, name="维生素")
    plan = MedicationPlan(
        owner=user,
        medicine=medicine,
        dosage_text="一粒",
        timezone="Asia/Shanghai",
        schedule_json=schedule_json,
    )

    with pytest.raises(ValidationError, match="schedule_json"):
        plan.full_clean()


@pytest.mark.django_db
def test_occurrence_idempotency_key_is_globally_unique(user):
    plan = create_plan(user)
    scheduled_at = datetime(2026, 8, 8, 0, 0, tzinfo=timezone.utc)
    MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=scheduled_at,
        index=0,
        idempotency_key="plan-001-0",
    )

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            MedicationOccurrence.objects.create(
                plan=plan,
                scheduled_at=scheduled_at,
                index=1,
                idempotency_key="plan-001-0",
            )


@pytest.mark.django_db
@pytest.mark.parametrize("status", ["taken", "skipped", "missed"])
def test_terminal_occurrence_status_requires_an_action_timestamp(user, status):
    plan = create_plan(user)
    occurrence = MedicationOccurrence(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, 0, tzinfo=timezone.utc),
        index=0,
        status=status,
        idempotency_key=f"terminal-{status}",
    )

    with pytest.raises(ValidationError, match="acted_at"):
        occurrence.full_clean()


@pytest.mark.django_db
def test_pending_occurrence_cannot_have_an_action_timestamp(user):
    plan = create_plan(user)
    occurrence = MedicationOccurrence(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, 0, tzinfo=timezone.utc),
        index=0,
        status=MedicationOccurrence.Status.PENDING,
        acted_at=datetime(2026, 8, 8, 0, 1, tzinfo=timezone.utc),
        idempotency_key="pending-with-action",
    )

    with pytest.raises(ValidationError, match="acted_at"):
        occurrence.full_clean()


@pytest.mark.django_db
def test_occurrence_scheduled_at_must_be_utc(user):
    plan = create_plan(user)
    occurrence = MedicationOccurrence(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 8, 0, tzinfo=ZoneInfo("Asia/Shanghai")),
        index=0,
        idempotency_key="non-utc-occurrence",
    )

    with pytest.raises(ValidationError, match="scheduled_at"):
        occurrence.full_clean()


@pytest.mark.django_db
def test_intake_event_is_unique_per_occurrence_and_tracks_user_action(user):
    plan = create_plan(user)
    occurrence = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, 0, tzinfo=timezone.utc),
        index=0,
        status=MedicationOccurrence.Status.TAKEN,
        acted_at=datetime(2026, 8, 8, 0, 1, tzinfo=timezone.utc),
        idempotency_key="taken-001",
    )
    event = IntakeEvent.objects.create(
        occurrence=occurrence,
        user=user,
        action=IntakeEvent.Action.TAKEN,
    )

    assert event.occurrence_id == occurrence.id
    assert event.user_id == user.id

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            IntakeEvent.objects.create(
                occurrence=occurrence,
                user=user,
                action=IntakeEvent.Action.TAKEN,
            )


@pytest.mark.django_db
def test_intake_event_must_be_recorded_by_the_plan_owner(user, django_user_model):
    plan = create_plan(user)
    occurrence = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, 0, tzinfo=timezone.utc),
        index=0,
        status=MedicationOccurrence.Status.TAKEN,
        acted_at=datetime(2026, 8, 8, 0, 1, tzinfo=timezone.utc),
        idempotency_key="taken-by-other-user",
    )
    another = django_user_model.objects.create_user(username="other-intake-user")
    event = IntakeEvent(
        occurrence=occurrence,
        user=another,
        action=IntakeEvent.Action.TAKEN,
    )

    with pytest.raises(ValidationError, match="user"):
        event.full_clean()


@pytest.mark.django_db
def test_intake_event_action_must_match_the_occurrence_status(user):
    plan = create_plan(user)
    occurrence = MedicationOccurrence.objects.create(
        plan=plan,
        scheduled_at=datetime(2026, 8, 8, 0, 0, tzinfo=timezone.utc),
        index=0,
        status=MedicationOccurrence.Status.SKIPPED,
        acted_at=datetime(2026, 8, 8, 0, 1, tzinfo=timezone.utc),
        idempotency_key="skipped-with-taken-event",
    )
    event = IntakeEvent(
        occurrence=occurrence,
        user=user,
        action=IntakeEvent.Action.TAKEN,
    )

    with pytest.raises(ValidationError, match="action"):
        event.full_clean()

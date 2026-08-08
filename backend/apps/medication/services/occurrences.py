from datetime import date, datetime, time, timedelta, timezone as datetime_timezone
from zoneinfo import ZoneInfo

from django.db import IntegrityError, transaction

from apps.medication.models import MedicationOccurrence, MedicationPlan


EPOCH = date(1970, 1, 1)


def materialize_occurrences(
    plan: MedicationPlan, *, now: datetime, days: int = 30
) -> list[MedicationOccurrence]:
    if days < 1:
        raise ValueError("days must be positive")
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")
    if not plan.enabled:
        return []

    timezone = ZoneInfo(plan.timezone)
    first_local_date = now.astimezone(timezone).date()
    created = []
    for offset in range(days):
        local_date = first_local_date + timedelta(days=offset)
        for time_text in plan.schedule_json["times"]:
            local_time = time.fromisoformat(time_text)
            local_value = datetime.combine(local_date, local_time, tzinfo=timezone)
            scheduled_at = local_value.astimezone(datetime_timezone.utc)
            index = _index_for(local_date, local_time)
            occurrence, was_created = _get_or_create_occurrence(
                plan=plan,
                index=index,
                scheduled_at=scheduled_at,
            )
            if was_created:
                created.append(occurrence)
    return created


def materialize_enabled_plans(*, now: datetime, batch_size: int = 100) -> list[MedicationPlan]:
    if batch_size < 1:
        raise ValueError("batch_size must be positive")
    changed = []
    for plan in (
        MedicationPlan.objects.filter(enabled=True)
        .order_by("id")
        .iterator(chunk_size=batch_size)
    ):
        if materialize_occurrences(plan, now=now):
            changed.append(plan)
    return changed


def _index_for(local_date: date, local_time: time) -> int:
    return (local_date - EPOCH).days * 1440 + local_time.hour * 60 + local_time.minute


def _get_or_create_occurrence(*, plan, index, scheduled_at):
    defaults = {
        "scheduled_at": scheduled_at,
        "idempotency_key": f"medication:{plan.id}:{index}",
    }
    try:
        with transaction.atomic():
            return MedicationOccurrence.objects.get_or_create(
                plan=plan,
                index=index,
                defaults=defaults,
            )
    except IntegrityError:
        return MedicationOccurrence.objects.get(plan=plan, index=index), False

from uuid import UUID

from apps.medication.models import MedicationPlan
from apps.medication.services.dosage import parse_structured_dose
from apps.medication.services.occurrences import materialize_occurrences
from apps.medicines.models import MedicineItem
from apps.medicines.services.access import medicine_access_query


def ensure_medication_plan_for_workflow(*, draft, task, now):
    if task.template_hint != "medication_cycle":
        return None
    existing = MedicationPlan.objects.filter(source_workflow_draft=draft).first()
    if existing is not None:
        return existing

    slots = task.slots
    medicine_name = slots["medicine_name"]
    dosage_text = slots["dose_text"]
    dose_quantity, dose_unit = parse_structured_dose(dosage_text)
    medicine = _resolve_medicine(
        draft.user,
        medicine_name,
        medicine_id=slots.get("medicine_id"),
        dose_unit=dose_unit,
    )
    times = slots.get("times")
    if not isinstance(times, list) or not all(
        isinstance(value, str) for value in times
    ):
        times = [slots["time_of_day"]]
    plan = MedicationPlan(
        owner=draft.user,
        medicine=medicine,
        medicine_name=medicine_name,
        source_workflow_draft=draft,
        dosage_text=dosage_text,
        dose_quantity=dose_quantity,
        dose_unit=dose_unit,
        timezone="Asia/Shanghai",
        schedule_json={"times": times},
    )
    plan.full_clean()
    plan.save()
    materialize_occurrences(plan, now=now)
    return plan


def _resolve_medicine(user, medicine_name, *, medicine_id=None, dose_unit=""):
    if medicine_id:
        if not isinstance(medicine_id, str):
            return None
        try:
            selected_id = UUID(medicine_id)
        except ValueError:
            return None
        return (
            MedicineItem.objects.filter(medicine_access_query(user), id=selected_id)
            .distinct()
            .first()
        )

    candidates = list(
        MedicineItem.objects.filter(
            medicine_access_query(user), name__iexact=medicine_name
        )
        .distinct()
        .prefetch_related("batches")
    )
    if not candidates:
        return None

    ranked = sorted(
        (
            (candidate, _medicine_match_score(candidate, user, dose_unit))
            for candidate in candidates
        ),
        key=lambda item: (item[1], item[0].created_at, str(item[0].id)),
        reverse=True,
    )
    best_score = ranked[0][1]
    best = [candidate for candidate, score in ranked if score == best_score]
    return best[0] if len(best) == 1 else None


def _medicine_match_score(medicine, user, dose_unit):
    batches = list(medicine.batches.all())
    has_matching_unit = bool(dose_unit) and any(
        batch.units_per_package is not None and batch.unit_name == dose_unit
        for batch in batches
    )
    has_precise_inventory = any(
        batch.units_per_package is not None and bool(batch.unit_name)
        for batch in batches
    )
    return (
        2 if has_matching_unit else 1 if has_precise_inventory else 0,
        1 if medicine.owner_id == user.id else 0,
    )

from apps.medication.models import MedicationPlan
from apps.medication.services.dosage import parse_structured_dose
from apps.medication.services.occurrences import materialize_occurrences
from apps.medicines.models import MedicineItem


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
    medicine = _resolve_medicine(draft.user, medicine_name)
    plan = MedicationPlan(
        owner=draft.user,
        medicine=medicine,
        medicine_name=medicine_name,
        source_workflow_draft=draft,
        dosage_text=dosage_text,
        dose_quantity=dose_quantity,
        dose_unit=dose_unit,
        timezone="Asia/Shanghai",
        schedule_json={"times": [slots["time_of_day"]]},
    )
    plan.full_clean()
    plan.save()
    materialize_occurrences(plan, now=now)
    return plan


def _resolve_medicine(user, medicine_name):
    personal = list(
        MedicineItem.objects.filter(owner=user, name__iexact=medicine_name)[:2]
    )
    if len(personal) == 1:
        return personal[0]
    if personal:
        return None
    family = list(
        MedicineItem.objects.filter(
            family__members__user=user,
            name__iexact=medicine_name,
        ).distinct()[:2]
    )
    return family[0] if len(family) == 1 else None

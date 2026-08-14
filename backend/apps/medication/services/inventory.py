from decimal import Decimal
from zoneinfo import ZoneInfo

from django.utils import timezone

from apps.families.services import record_event
from apps.medication.models import (
    IntakeEvent,
    InventoryDeductionAttempt,
    InventoryDeductionEntry,
)
from apps.medicines.models import InventoryBatch, MedicineItem
from apps.medicines.services.access import medicine_access_query


STATUS_MESSAGES = {
    InventoryDeductionAttempt.Status.DISABLED: "已记录服药，当前计划未启用自动扣减",
    InventoryDeductionAttempt.Status.MEDICINE_UNLINKED: "已记录服药，但计划尚未关联药箱药品",
    InventoryDeductionAttempt.Status.NOT_CONFIGURED: "已记录服药，但药箱未记录精确剩余量",
    InventoryDeductionAttempt.Status.UNIT_MISMATCH: "已记录服药，但计划剂量与药箱计量单位不一致",
    InventoryDeductionAttempt.Status.INSUFFICIENT: "已记录服药，但药箱库存不足，未自动扣减",
    InventoryDeductionAttempt.Status.ACCESS_DENIED: "已记录服药，但当前已无权修改该药箱库存",
}


def deduct_inventory_for_intake(event: IntakeEvent):
    existing = InventoryDeductionAttempt.objects.filter(intake_event=event).first()
    if existing is not None:
        return existing

    plan = event.occurrence.plan
    requested = plan.dose_quantity
    unit_name = plan.dose_unit
    if not plan.auto_deduct_inventory:
        return _record_attempt(event, InventoryDeductionAttempt.Status.DISABLED)
    if plan.medicine_id is None:
        return _record_attempt(
            event,
            InventoryDeductionAttempt.Status.MEDICINE_UNLINKED,
            requested=requested,
            unit_name=unit_name,
        )
    if requested is None or not unit_name:
        return _record_attempt(
            event,
            InventoryDeductionAttempt.Status.NOT_CONFIGURED,
            requested=requested,
            unit_name=unit_name,
        )
    if not MedicineItem.objects.filter(
        medicine_access_query(event.user), id=plan.medicine_id
    ).exists():
        return _record_attempt(
            event,
            InventoryDeductionAttempt.Status.ACCESS_DENIED,
            requested=requested,
            unit_name=unit_name,
        )

    batches = list(
        InventoryBatch.objects.select_for_update()
        .filter(medicine_id=plan.medicine_id, units_per_package__isnull=False)
        .exclude(unit_name="")
    )
    if not batches:
        return _record_attempt(
            event,
            InventoryDeductionAttempt.Status.NOT_CONFIGURED,
            requested=requested,
            unit_name=unit_name,
        )
    matching = [batch for batch in batches if batch.unit_name == unit_name]
    if not matching:
        return _record_attempt(
            event,
            InventoryDeductionAttempt.Status.UNIT_MISMATCH,
            requested=requested,
            unit_name=unit_name,
        )

    local_today = timezone.localdate(timezone=ZoneInfo(plan.timezone))
    eligible = [
        batch
        for batch in matching
        if batch.total_remaining_units > 0
        and (batch.effective_deadline is None or batch.effective_deadline >= local_today)
    ]
    eligible.sort(
        key=lambda batch: (
            batch.effective_deadline is None,
            batch.effective_deadline or local_today,
            batch.created_at,
            str(batch.id),
        )
    )
    available = sum(
        (batch.total_remaining_units for batch in eligible),
        start=Decimal("0"),
    )
    if available < requested:
        return _record_attempt(
            event,
            InventoryDeductionAttempt.Status.INSUFFICIENT,
            requested=requested,
            unit_name=unit_name,
            remaining=available,
        )

    attempt = _record_attempt(
        event,
        InventoryDeductionAttempt.Status.DEDUCTED,
        requested=requested,
        deducted=requested,
        unit_name=unit_name,
        remaining=available - requested,
    )
    needed = requested
    for batch in eligible:
        if needed <= 0:
            break
        before = batch.total_remaining_units
        deducted = min(before, needed)
        _deduct_from_batch(batch, deducted)
        batch.version += 1
        batch.updated_by = event.user
        batch.full_clean()
        batch.save(
            update_fields=[
                "quantity",
                "loose_units",
                "version",
                "updated_by",
                "updated_at",
            ]
        )
        InventoryDeductionEntry.objects.create(
            attempt=attempt,
            batch=batch,
            quantity=deducted,
            before_quantity=before,
            after_quantity=batch.total_remaining_units,
        )
        needed -= deducted

    family = plan.medicine.family
    if family is not None:
        record_event(
            family=family,
            actor=event.user,
            event_type="inventory_consumed",
            payload={
                "attempt_id": str(attempt.id),
                "medicine_id": str(plan.medicine_id),
                "quantity": str(requested),
                "unit": unit_name,
            },
        )
    return attempt


def deduction_payload(attempt: InventoryDeductionAttempt):
    message = STATUS_MESSAGES.get(attempt.status)
    if attempt.status == InventoryDeductionAttempt.Status.DEDUCTED:
        deducted = _decimal_text(attempt.deducted_quantity)
        remaining = _decimal_text(attempt.remaining_quantity)
        message = (
            f"已记录服药，已扣减{deducted}{attempt.unit_name}，"
            f"精确库存剩余{remaining}{attempt.unit_name}"
        )
    return {
        "status": attempt.status,
        "deducted_quantity": _decimal_text(attempt.deducted_quantity),
        "unit": attempt.unit_name,
        "remaining_quantity": (
            _decimal_text(attempt.remaining_quantity)
            if attempt.remaining_quantity is not None
            else None
        ),
        "message": message,
    }


def _record_attempt(
    event,
    status,
    *,
    requested=None,
    deducted=Decimal("0"),
    unit_name="",
    remaining=None,
):
    return InventoryDeductionAttempt.objects.create(
        intake_event=event,
        status=status,
        requested_quantity=requested,
        deducted_quantity=deducted,
        unit_name=unit_name,
        remaining_quantity=remaining,
    )


def _deduct_from_batch(batch: InventoryBatch, quantity: Decimal):
    needed = quantity
    from_loose = min(batch.loose_units, needed)
    batch.loose_units -= from_loose
    needed -= from_loose
    while needed > 0:
        batch.quantity -= 1
        consumed = min(batch.units_per_package, needed)
        batch.loose_units = batch.units_per_package - consumed
        needed -= consumed


def _decimal_text(value: Decimal):
    return format(value.normalize(), "f")

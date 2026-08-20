from decimal import Decimal, ROUND_HALF_UP

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.medication.models import MedicationPlan
from apps.medicines.models import InventoryBatch, LowStockAlertState, MedicineItem


DEFAULT_LOW_STOCK_THRESHOLD_DAYS = 3


@transaction.atomic
def refresh_low_stock_alerts_for_medicine(
    *,
    medicine: MedicineItem,
    today,
    threshold_days: int = DEFAULT_LOW_STOCK_THRESHOLD_DAYS,
):
    """Refresh low-stock alerts for every precise unit used by active plans."""
    if threshold_days < 1:
        raise ValueError("threshold_days must be positive")

    medicine = MedicineItem.objects.select_for_update().get(id=medicine.id)
    unit_names = set(
        MedicationPlan.objects.filter(
            medicine=medicine,
            enabled=True,
            auto_deduct_inventory=True,
            dose_quantity__isnull=False,
        )
        .exclude(dose_unit="")
        .values_list("dose_unit", flat=True)
    )
    refreshed = []
    for unit_name in sorted(unit_names):
        alert = _refresh_unit(
            medicine=medicine,
            unit_name=unit_name,
            today=today,
            threshold_days=threshold_days,
        )
        if alert is not None:
            refreshed.append(alert)

    LowStockAlertState.objects.filter(
        medicine=medicine,
        threshold_days=threshold_days,
    ).exclude(unit_name__in=unit_names).filter(
        status=LowStockAlertState.Status.ACTIVE,
    ).update(
        status=LowStockAlertState.Status.SUPERSEDED,
    )
    return refreshed


def refresh_low_stock_alerts_for_batch(
    *,
    batch: InventoryBatch,
    today,
    threshold_days: int = DEFAULT_LOW_STOCK_THRESHOLD_DAYS,
):
    return refresh_low_stock_alerts_for_medicine(
        medicine=batch.medicine,
        today=today,
        threshold_days=threshold_days,
    )


def resolve_low_stock_alert(*, alert: LowStockAlertState):
    alert = LowStockAlertState.objects.select_for_update().get(id=alert.id)
    if alert.status != LowStockAlertState.Status.RESOLVED:
        alert.status = LowStockAlertState.Status.RESOLVED
        alert.resolved_at = timezone.now()
        alert.save(update_fields=["status", "resolved_at", "updated_at"])
    return alert


def _refresh_unit(*, medicine, unit_name, today, threshold_days):
    daily_quantity = _daily_quantity(medicine=medicine, unit_name=unit_name)
    remaining = _remaining_quantity(
        medicine=medicine,
        unit_name=unit_name,
        today=today,
    )
    existing = LowStockAlertState.objects.filter(
        medicine=medicine,
        unit_name=unit_name,
        threshold_days=threshold_days,
    ).first()

    if daily_quantity <= 0 or remaining is None:
        if existing is not None and existing.status == LowStockAlertState.Status.ACTIVE:
            existing.status = LowStockAlertState.Status.SUPERSEDED
            existing.save(update_fields=["status", "updated_at"])
        return None

    threshold_quantity = daily_quantity * Decimal(threshold_days)
    days_remaining = _days_remaining(remaining, daily_quantity)
    if remaining > threshold_quantity:
        if existing is not None and existing.status == LowStockAlertState.Status.ACTIVE:
            existing.status = LowStockAlertState.Status.RESOLVED
            existing.remaining_quantity = remaining
            existing.daily_quantity = daily_quantity
            existing.days_remaining = days_remaining
            existing.resolved_at = timezone.now()
            existing.save(
                update_fields=[
                    "status",
                    "remaining_quantity",
                    "daily_quantity",
                    "days_remaining",
                    "resolved_at",
                    "updated_at",
                ]
            )
        return existing

    alert, _ = LowStockAlertState.objects.get_or_create(
        medicine=medicine,
        unit_name=unit_name,
        threshold_days=threshold_days,
        defaults={
            "remaining_quantity": remaining,
            "daily_quantity": daily_quantity,
            "days_remaining": days_remaining,
        },
    )
    update_fields = [
        "remaining_quantity",
        "daily_quantity",
        "days_remaining",
        "updated_at",
    ]
    alert.remaining_quantity = remaining
    alert.daily_quantity = daily_quantity
    alert.days_remaining = days_remaining
    if alert.status != LowStockAlertState.Status.ACTIVE:
        alert.status = LowStockAlertState.Status.ACTIVE
        alert.activated_at = timezone.now()
        alert.resolved_at = None
        update_fields.extend(["status", "activated_at", "resolved_at"])
    alert.save(update_fields=update_fields)
    return alert


def _daily_quantity(*, medicine, unit_name):
    total = Decimal("0")
    plans = MedicationPlan.objects.filter(
        medicine=medicine,
        enabled=True,
        auto_deduct_inventory=True,
        dose_quantity__isnull=False,
        dose_unit=unit_name,
    )
    for plan in plans:
        times = plan.schedule_json.get("times") if isinstance(plan.schedule_json, dict) else []
        if not isinstance(times, list):
            continue
        total += plan.dose_quantity * Decimal(len(times))
    return total


def _remaining_quantity(*, medicine, unit_name, today):
    batches = InventoryBatch.objects.filter(
        medicine=medicine,
        unit_name=unit_name,
        units_per_package__isnull=False,
    ).filter(Q(expiry_date__isnull=True) | Q(expiry_date__gte=today))
    total = Decimal("0")
    has_precise_batch = False
    for batch in batches:
        remaining = batch.total_remaining_units
        if remaining is None:
            continue
        if batch.effective_deadline is not None and batch.effective_deadline < today:
            continue
        has_precise_batch = True
        total += remaining
    return total if has_precise_batch else None


def _days_remaining(remaining, daily_quantity):
    return (remaining / daily_quantity).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

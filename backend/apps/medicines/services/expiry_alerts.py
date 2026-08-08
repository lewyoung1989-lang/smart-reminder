from datetime import date

from django.db import transaction
from django.utils import timezone

from apps.medicines.models import ExpiryAlertState, InventoryBatch
from apps.medicines.services.expiry import expiry_threshold_dates


@transaction.atomic
def refresh_expiry_alerts(*, batch: InventoryBatch, today: date):
    """同步单个批次的阈值状态，并只激活当前最严重的已跨越阈值。"""
    batch = InventoryBatch.objects.select_for_update().get(id=batch.id)
    deadline = batch.effective_deadline
    active_statuses = (
        ExpiryAlertState.Status.PENDING,
        ExpiryAlertState.Status.ACTIVE,
        ExpiryAlertState.Status.COVERED,
    )
    stale_states = batch.expiry_alerts.filter(status__in=active_statuses)
    if deadline is None:
        stale_states.update(status=ExpiryAlertState.Status.SUPERSEDED)
        return None

    stale_states.exclude(deadline=deadline).update(
        status=ExpiryAlertState.Status.SUPERSEDED
    )
    current_states = {}
    for threshold_days, _ in expiry_threshold_dates(deadline):
        state, _ = ExpiryAlertState.objects.get_or_create(
            batch=batch,
            threshold_days=threshold_days,
            deadline=deadline,
        )
        current_states[threshold_days] = state

    crossed_thresholds = [
        threshold_days
        for threshold_days, trigger_date in expiry_threshold_dates(deadline)
        if trigger_date <= today
    ]
    if not crossed_thresholds:
        return None

    selected_threshold = min(crossed_thresholds)
    now = timezone.now()
    selected = current_states[selected_threshold]
    for threshold_days, state in current_states.items():
        if state.status == ExpiryAlertState.Status.RESOLVED:
            continue
        if threshold_days == selected_threshold:
            if state.status != ExpiryAlertState.Status.ACTIVE:
                state.status = ExpiryAlertState.Status.ACTIVE
                state.activated_at = now
                state.save(update_fields=["status", "activated_at", "updated_at"])
        elif threshold_days in crossed_thresholds:
            if state.status != ExpiryAlertState.Status.COVERED:
                state.status = ExpiryAlertState.Status.COVERED
                state.covered_at = now
                state.save(update_fields=["status", "covered_at", "updated_at"])
    return selected

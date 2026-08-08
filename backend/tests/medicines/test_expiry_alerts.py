from datetime import date

import pytest

from apps.medicines.models import InventoryBatch, MedicineItem


@pytest.mark.django_db
def test_expiry_alert_state_only_surfaces_the_most_severe_crossed_threshold(user):
    """跨过多个阈值时，只保留当前最严重的一条待处理提醒。"""
    from apps.medicines.services.expiry_alerts import refresh_expiry_alerts

    medicine = MedicineItem.objects.create(owner=user, name="滴眼液")
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date=date(2026, 8, 8),
    )

    actionable = refresh_expiry_alerts(batch=batch, today=date(2026, 8, 9))

    assert actionable.threshold_days == 0
    states = list(batch.expiry_alerts.order_by("threshold_days"))
    assert [(state.threshold_days, state.status) for state in states] == [
        (0, "active"),
        (7, "covered"),
        (30, "covered"),
        (90, "covered"),
    ]


@pytest.mark.django_db
def test_expiry_alert_refresh_is_idempotent_and_keeps_expired_item_actionable(user):
    from apps.medicines.services.expiry_alerts import refresh_expiry_alerts

    medicine = MedicineItem.objects.create(owner=user, name="感冒药")
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date=date(2026, 8, 8),
    )

    first = refresh_expiry_alerts(batch=batch, today=date(2026, 8, 9))
    second = refresh_expiry_alerts(batch=batch, today=date(2026, 8, 10))

    assert first.id == second.id
    assert first.status == "active"
    assert batch.expiry_alerts.count() == 4


@pytest.mark.django_db
def test_expiry_alert_refresh_replaces_states_after_deadline_correction(user):
    from apps.medicines.services.expiry_alerts import refresh_expiry_alerts

    medicine = MedicineItem.objects.create(owner=user, name="维生素")
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date=date(2026, 8, 8),
    )
    refresh_expiry_alerts(batch=batch, today=date(2026, 8, 9))

    batch.expiry_date = date(2027, 1, 1)
    batch.save(update_fields=["expiry_date"])
    actionable = refresh_expiry_alerts(batch=batch, today=date(2026, 8, 9))

    assert actionable is None
    assert set(
        batch.expiry_alerts.filter(deadline=date(2026, 8, 8)).values_list(
            "status", flat=True
        )
    ) == {"superseded"}

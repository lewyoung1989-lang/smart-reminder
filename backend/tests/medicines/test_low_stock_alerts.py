from datetime import date

import pytest

from apps.medication.models import MedicationPlan
from apps.medicines.models import InventoryBatch, LowStockAlertState, MedicineItem
from apps.medicines.services.low_stock_alerts import refresh_low_stock_alerts_for_medicine


TODAY = date(2026, 8, 8)


@pytest.mark.django_db
def test_refresh_low_stock_alerts_uses_precise_inventory_and_daily_plans(user):
    medicine = MedicineItem.objects.create(owner=user, name="拜新同")
    MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        medicine_name="拜新同",
        dosage_text="1片",
        dose_quantity="1",
        dose_unit="片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    InventoryBatch.objects.create(
        medicine=medicine,
        quantity=0,
        package_unit="盒",
        units_per_package="14",
        unit_name="片",
        loose_units="2",
    )

    alerts = refresh_low_stock_alerts_for_medicine(medicine=medicine, today=TODAY)

    assert len(alerts) == 1
    alert = LowStockAlertState.objects.get(medicine=medicine)
    assert alert.status == LowStockAlertState.Status.ACTIVE
    assert alert.remaining_quantity == 2
    assert alert.daily_quantity == 1
    assert alert.days_remaining == 2


@pytest.mark.django_db
def test_refresh_low_stock_alerts_resolves_after_restock(user):
    medicine = MedicineItem.objects.create(owner=user, name="拜新同")
    MedicationPlan.objects.create(
        owner=user,
        medicine=medicine,
        medicine_name="拜新同",
        dosage_text="1片",
        dose_quantity="1",
        dose_unit="片",
        timezone="Asia/Shanghai",
        schedule_json={"times": ["08:00"]},
    )
    InventoryBatch.objects.create(
        medicine=medicine,
        quantity=0,
        package_unit="盒",
        units_per_package="14",
        unit_name="片",
        loose_units="2",
    )
    refresh_low_stock_alerts_for_medicine(medicine=medicine, today=TODAY)
    InventoryBatch.objects.create(
        medicine=medicine,
        quantity=1,
        package_unit="盒",
        units_per_package="14",
        unit_name="片",
        loose_units="0",
    )

    refresh_low_stock_alerts_for_medicine(medicine=medicine, today=TODAY)

    alert = LowStockAlertState.objects.get(medicine=medicine)
    assert alert.status == LowStockAlertState.Status.RESOLVED
    assert alert.remaining_quantity == 16
    assert alert.resolved_at is not None

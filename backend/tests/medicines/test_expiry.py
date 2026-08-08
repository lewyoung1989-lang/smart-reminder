from datetime import date

import pytest
from django.core.exceptions import ValidationError

from apps.medicines.models import InventoryBatch, MedicineItem


@pytest.mark.django_db
def test_inventory_batch_uses_earliest_manufacturer_or_opened_deadline(user):
    medicine = MedicineItem.objects.create(owner=user, name="滴眼液")
    batch = InventoryBatch.objects.create(
        medicine=medicine,
        expiry_date=date(2027, 1, 1),
        opened_at=date(2026, 8, 1),
        opened_shelf_life_days=28,
    )

    assert batch.effective_deadline == date(2026, 8, 29)


@pytest.mark.django_db
def test_inventory_batch_requires_opened_date_and_positive_lifetime_together(user):
    medicine = MedicineItem.objects.create(owner=user, name="滴眼液")
    batch = InventoryBatch(
        medicine=medicine,
        opened_at=date(2026, 8, 1),
        opened_shelf_life_days=None,
    )

    with pytest.raises(ValidationError, match="opened_shelf_life_days"):
        batch.full_clean()

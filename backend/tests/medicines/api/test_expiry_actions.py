from datetime import date

import pytest

from apps.medicines.models import (
    ExpiryAlertState,
    ExpiryBatchAction,
    InventoryBatch,
    MedicineItem,
)


@pytest.mark.django_db
def test_marking_expired_batch_handled_resolves_active_alert_and_records_audit(
    api_client, user
):
    medicine = MedicineItem.objects.create(owner=user, name="滴眼液")
    batch = InventoryBatch.objects.create(medicine=medicine, expiry_date=date(2026, 8, 8))
    alert = ExpiryAlertState.objects.create(
        batch=batch,
        threshold_days=0,
        deadline=date(2026, 8, 8),
        status=ExpiryAlertState.Status.ACTIVE,
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/inventory-batches/{batch.id}/expiry-actions",
        {"action": "handled"},
        format="json",
    )

    assert response.status_code == 200
    alert.refresh_from_db()
    assert alert.status == ExpiryAlertState.Status.RESOLVED
    assert response.json() == {"batch_id": str(batch.id), "action": "handled"}
    audit = batch.expiry_actions.get()
    assert audit.user == user
    assert audit.action == "handled"


@pytest.mark.django_db
def test_user_cannot_mark_another_users_expiry_batch_handled(
    api_client, user, django_user_model
):
    other_user = django_user_model.objects.create_user(
        username="other-user",
        email="other@example.com",
        password="password123",
    )
    medicine = MedicineItem.objects.create(owner=other_user, name="胰岛素")
    batch = InventoryBatch.objects.create(medicine=medicine, expiry_date=date(2026, 8, 8))
    alert = ExpiryAlertState.objects.create(
        batch=batch,
        threshold_days=0,
        deadline=date(2026, 8, 8),
        status=ExpiryAlertState.Status.ACTIVE,
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        f"/api/v1/inventory-batches/{batch.id}/expiry-actions",
        {"action": ExpiryBatchAction.Action.HANDLED},
        format="json",
    )

    assert response.status_code == 404
    alert.refresh_from_db()
    assert alert.status == ExpiryAlertState.Status.ACTIVE
    assert not ExpiryBatchAction.objects.exists()

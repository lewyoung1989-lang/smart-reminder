import logging
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlsplit

import pytest

from apps.medicines.models import InventoryBatch, MedicineItem


TODAY = date(2026, 8, 5)


def create_batch(
    *,
    owner,
    name,
    specification="",
    batch_number="",
    expiry_date=None,
    quantity=1,
):
    medicine = MedicineItem.objects.create(
        owner=owner,
        name=name,
        specification=specification,
    )
    return InventoryBatch.objects.create(
        medicine=medicine,
        batch_number=batch_number,
        expiry_date=expiry_date,
        quantity=quantity,
    )


@pytest.mark.django_db
def test_inventory_requires_authentication(api_client):
    response = api_client.get("/api/v1/inventory-batches")

    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


@pytest.mark.django_db
def test_inventory_batch_delete_requires_authentication(api_client, user):
    batch = create_batch(owner=user, name="布洛芬")

    response = api_client.delete(f"/api/v1/inventory-batches/{batch.id}")

    assert response.status_code == 401
    assert InventoryBatch.objects.filter(id=batch.id).exists()


@pytest.mark.django_db
def test_inventory_batch_create_requires_authentication(api_client):
    response = api_client.post(
        "/api/v1/inventory-batches",
        {"medicine_name": "布洛芬"},
    )

    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


@pytest.mark.django_db
def test_inventory_batch_create_adds_owned_medicine_and_refreshes_expiry_alert(
    api_client,
    user,
    mocker,
    caplog,
):
    refresh = mocker.patch("apps.medicines.api.views.refresh_expiry_alerts")
    mocker.patch(
        "apps.medicines.api.views.timezone.localdate",
        return_value=TODAY,
    )
    api_client.force_authenticate(user)
    caplog.set_level(logging.INFO, logger="apps.medicines.api.views")

    response = api_client.post(
        "/api/v1/inventory-batches",
        {
            "medicine_name": "布洛芬胶囊",
            "specification": "0.3g*20粒",
            "batch_number": "LOT-88",
            "production_date": "2026-01-01",
            "expiry_date": "2027-01-01",
            "quantity": 2,
        },
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["medicine_name"] == "布洛芬胶囊"
    assert payload["specification"] == "0.3g*20粒"
    assert payload["batch_number"] == "LOT-88"
    assert payload["quantity"] == 2
    medicine = MedicineItem.objects.get(owner=user)
    assert medicine.name == "布洛芬胶囊"
    batch = InventoryBatch.objects.get(medicine=medicine)
    assert str(batch.id) == payload["id"]
    refresh.assert_called_once_with(batch=batch, today=TODAY)
    assert f"batch_id={batch.id}" in caplog.text
    assert "布洛芬胶囊" not in caplog.text


@pytest.mark.django_db
def test_inventory_batch_create_reuses_same_owned_medicine(api_client, user):
    medicine = MedicineItem.objects.create(
        owner=user,
        name="维生素C",
        specification="100mg",
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/inventory-batches",
        {
            "medicine_name": "维生素C",
            "specification": "100mg",
            "quantity": 3,
        },
        format="json",
    )

    assert response.status_code == 201
    assert MedicineItem.objects.count() == 1
    assert InventoryBatch.objects.get().medicine_id == medicine.id


@pytest.mark.django_db
def test_inventory_batch_create_rejects_invalid_dates(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        "/api/v1/inventory-batches",
        {
            "medicine_name": "布洛芬",
            "production_date": "2027-01-01",
            "expiry_date": "2026-01-01",
        },
        format="json",
    )

    assert response.status_code == 400
    assert response.json()["expiry_date"] == ["有效期不能早于生产日期。"]
    assert InventoryBatch.objects.count() == 0


@pytest.mark.django_db
def test_inventory_batch_delete_removes_only_owned_batch(
    api_client,
    user,
    caplog,
):
    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    removed = InventoryBatch.objects.create(
        medicine=medicine,
        batch_number="A",
    )
    kept = InventoryBatch.objects.create(
        medicine=medicine,
        batch_number="B",
    )
    api_client.force_authenticate(user)
    caplog.set_level(logging.INFO, logger="apps.medicines.api.views")

    response = api_client.delete(
        f"/api/v1/inventory-batches/{removed.id}"
    )

    assert response.status_code == 204
    assert not InventoryBatch.objects.filter(id=removed.id).exists()
    assert InventoryBatch.objects.filter(id=kept.id).exists()
    assert MedicineItem.objects.filter(id=medicine.id).exists()
    assert f"batch_id={removed.id}" in caplog.text
    assert "布洛芬" not in caplog.text


@pytest.mark.django_db
def test_inventory_batch_delete_hides_other_users_batch(
    api_client,
    user,
    django_user_model,
):
    another = django_user_model.objects.create_user(username="other-delete")
    batch = create_batch(owner=another, name="他人药品")
    api_client.force_authenticate(user)

    response = api_client.delete(f"/api/v1/inventory-batches/{batch.id}")

    assert response.status_code == 404
    assert InventoryBatch.objects.filter(id=batch.id).exists()


@pytest.mark.django_db
def test_inventory_is_owner_scoped_and_orders_expiry_risk(
    api_client,
    user,
    django_user_model,
    mocker,
):
    another = django_user_model.objects.create_user(username="other-inventory")
    create_batch(
        owner=another,
        name="不应出现",
        expiry_date=TODAY - timedelta(days=10),
    )
    create_batch(
        owner=user,
        name="已过期药品",
        expiry_date=TODAY - timedelta(days=1),
    )
    create_batch(
        owner=user,
        name="临期药品",
        expiry_date=TODAY + timedelta(days=30),
    )
    create_batch(
        owner=user,
        name="有效药品",
        expiry_date=TODAY + timedelta(days=31),
    )
    create_batch(owner=user, name="日期未知药品")
    mocker.patch(
        "apps.medicines.api.serializers.timezone.localdate",
        return_value=TODAY,
    )
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/inventory-batches")

    assert response.status_code == 200
    payload = response.json()
    assert payload["next"] is None
    assert [item["medicine_name"] for item in payload["results"]] == [
        "已过期药品",
        "临期药品",
        "有效药品",
        "日期未知药品",
    ]
    assert [item["expiry_status"] for item in payload["results"]] == [
        "expired",
        "expiring_soon",
        "valid",
        "unknown",
    ]
    assert [item["days_until_expiry"] for item in payload["results"]] == [
        -1,
        30,
        31,
        None,
    ]


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("query", "expected_name"),
    [
        ("布洛芬", "布洛芬胶囊"),
        ("20粒", "规格命中"),
        ("LOT-88", "批号命中"),
    ],
)
def test_inventory_searches_name_specification_and_batch(
    api_client,
    user,
    query,
    expected_name,
):
    create_batch(owner=user, name="布洛芬胶囊")
    create_batch(owner=user, name="规格命中", specification="0.3g*20粒")
    create_batch(owner=user, name="批号命中", batch_number="LOT-88")
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/inventory-batches", {"q": query})

    assert response.status_code == 200
    assert [item["medicine_name"] for item in response.json()["results"]] == [
        expected_name
    ]


@pytest.mark.django_db
def test_inventory_uses_fifty_item_cursor_pages(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="家庭常备药")
    InventoryBatch.objects.bulk_create(
        [
            InventoryBatch(
                medicine=medicine,
                batch_number=f"BATCH-{index:03d}",
                expiry_date=TODAY + timedelta(days=index),
            )
            for index in range(51)
        ]
    )
    api_client.force_authenticate(user)

    first = api_client.get("/api/v1/inventory-batches")

    assert first.status_code == 200
    assert len(first.json()["results"]) == 50
    assert first.json()["next"] is not None
    next_url = urlsplit(first.json()["next"])
    second = api_client.get(f"{next_url.path}?{next_url.query}")
    assert second.status_code == 200
    assert len(second.json()["results"]) == 1


@pytest.mark.django_db
def test_inventory_expiry_uses_shanghai_calendar_date(
    api_client,
    user,
    mocker,
):
    create_batch(
        owner=user,
        name="上海日期边界",
        expiry_date=date(2026, 8, 5),
    )
    mocker.patch(
        "apps.medicines.api.serializers.timezone.now",
        return_value=datetime(2026, 8, 4, 16, 30, tzinfo=timezone.utc),
    )
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/inventory-batches")

    assert response.status_code == 200
    item = response.json()["results"][0]
    assert item["expiry_status"] == "expiring_soon"
    assert item["days_until_expiry"] == 0


@pytest.mark.django_db
def test_inventory_exposes_opened_lifetime_and_effective_deadline(api_client, user):
    batch = create_batch(
        owner=user,
        name="滴眼液",
        expiry_date=date(2027, 1, 1),
    )
    batch.opened_at = date(2026, 8, 1)
    batch.opened_shelf_life_days = 28
    batch.save(update_fields=["opened_at", "opened_shelf_life_days"])
    api_client.force_authenticate(user)

    response = api_client.get("/api/v1/inventory-batches")

    assert response.status_code == 200
    item = response.json()["results"][0]
    assert item["opened_at"] == "2026-08-01"
    assert item["opened_shelf_life_days"] == 28
    assert item["opened_use_before"] == "2026-08-29"
    assert item["effective_deadline"] == "2026-08-29"

from datetime import date
from decimal import Decimal

import pytest

from apps.families.models import Family, FamilyAuditEvent, FamilyMember
from apps.medication.models import MedicationPlan
from apps.medicines.models import ExpiryBatchAction, InventoryBatch, MedicineItem


@pytest.fixture
def stock(user):
    medicine = MedicineItem.objects.create(owner=user, name="库存测试药", specification="10mg")
    return InventoryBatch.objects.create(
        medicine=medicine, quantity=2, package_unit="盒",
        units_per_package=Decimal("20"), unit_name="片", loose_units=Decimal("5"),
        production_date=date(2026, 1, 1), expiry_date=date(2028, 1, 1),
    )


@pytest.mark.django_db
def test_update_stock_and_details_keeps_plan_and_writes_audit(api_client, user, stock):
    plan = MedicationPlan.objects.create(
        owner=user, medicine=stock.medicine,
        dosage_text="每次一片", schedule_json={"times": ["08:00"]},
    )
    sibling = InventoryBatch.objects.create(medicine=stock.medicine, quantity=1)
    api_client.force_authenticate(user)
    response = api_client.patch(f"/api/v1/inventory-batches/{stock.id}", {
        "version": 1, "medicine_name": "修改后的测试药", "specification": "20mg",
        "manufacturer": "测试生产公司", "quantity": 0, "loose_units": "8.5",
        "expiry_date": "2028-06-30",
    }, format="json")
    assert response.status_code == 200, response.data
    assert response.data["total_remaining_units"] == "8.5"
    assert response.data["version"] == 2
    stock.refresh_from_db()
    sibling.refresh_from_db()
    plan.refresh_from_db()
    assert stock.quantity == 0
    assert stock.medicine.name == "修改后的测试药"
    assert stock.medicine.manufacturer == "测试生产公司"
    assert sibling.version == 2
    assert plan.medicine_id == stock.medicine_id
    audit = ExpiryBatchAction.objects.get(batch=stock)
    assert audit.change_json["loose_units"] == {"old": "5.000", "new": "8.500"}


@pytest.mark.django_db
def test_stale_inventory_version_does_not_overwrite_intake(api_client, user, stock):
    stock.loose_units = Decimal("4")
    stock.version = 2
    stock.save()
    api_client.force_authenticate(user)
    response = api_client.patch(f"/api/v1/inventory-batches/{stock.id}", {
        "version": 1, "quantity": 5, "loose_units": "5",
    }, format="json")
    assert response.status_code == 409
    stock.refresh_from_db()
    assert stock.quantity == 2
    assert stock.loose_units == Decimal("4")
    assert not ExpiryBatchAction.objects.exists()


@pytest.mark.django_db
@pytest.mark.parametrize("changes", [
    {"quantity": -1}, {"quantity": 1.5}, {"quantity": 10000},
    {"loose_units": "20"}, {"units_per_package": None},
    {"expiry_date": "2025-01-01"}, {"medicine_name": ""},
    {"loose_units": "NaN"}, {"loose_units": "1.2345"},
])
def test_invalid_edit_rolls_back(api_client, user, stock, changes):
    api_client.force_authenticate(user)
    response = api_client.patch(f"/api/v1/inventory-batches/{stock.id}", {
        "version": 1, "manufacturer": "不得保存", **changes,
    }, format="json")
    assert response.status_code == 400
    stock.refresh_from_db()
    assert stock.version == 1
    assert stock.quantity == 2
    assert stock.medicine.manufacturer == ""


@pytest.mark.django_db
def test_update_requires_version_and_authentication(api_client, user, stock):
    url = f"/api/v1/inventory-batches/{stock.id}"
    assert api_client.patch(url, {"quantity": 1}, format="json").status_code == 401
    api_client.force_authenticate(user)
    assert api_client.patch(url, {"quantity": 1}, format="json").status_code == 400
    assert api_client.patch(url, {"version": 1}, format="json").status_code == 400


@pytest.mark.django_db
def test_other_users_cannot_update_stock(api_client, django_user_model, stock):
    api_client.force_authenticate(django_user_model.objects.create_user(username="outsider"))
    response = api_client.patch(f"/api/v1/inventory-batches/{stock.id}", {
        "version": 1, "quantity": 8,
    }, format="json")
    assert response.status_code == 404


@pytest.mark.django_db
def test_family_member_can_edit_with_audit_but_removed_member_cannot(api_client, user, stock):
    family = Family.objects.create(name="测试家庭")
    membership = FamilyMember.objects.create(family=family, user=user, nickname="成员")
    medicine = stock.medicine
    medicine.owner = None
    medicine.family = family
    medicine.save()
    api_client.force_authenticate(user)
    url = f"/api/v1/inventory-batches/{stock.id}"
    response = api_client.patch(url, {"version": 1, "quantity": 3}, format="json")
    assert response.status_code == 200, response.data
    assert FamilyAuditEvent.objects.filter(family=family, actor=user, event_type="inventory_corrected").exists()
    membership.delete()
    assert api_client.patch(url, {"version": 2, "quantity": 4}, format="json").status_code == 404


@pytest.mark.django_db
def test_duplicate_name_is_validation_error_not_server_error(api_client, user, stock):
    MedicineItem.objects.create(owner=user, name="另一个药品", specification="10mg")
    api_client.force_authenticate(user)
    response = api_client.patch(f"/api/v1/inventory-batches/{stock.id}", {
        "version": 1, "medicine_name": "另一个药品", "quantity": 3,
    }, format="json")
    assert response.status_code == 400
    stock.refresh_from_db()
    assert stock.quantity == 2


@pytest.mark.django_db
def test_switch_precision_and_clear_dates(api_client, user, stock):
    api_client.force_authenticate(user)
    response = api_client.patch(f"/api/v1/inventory-batches/{stock.id}", {
        "version": 1, "quantity": 0, "package_unit": "", "unit_name": "",
        "units_per_package": None, "loose_units": "0",
        "production_date": None, "expiry_date": None,
    }, format="json")
    assert response.status_code == 200, response.data
    assert response.data["total_remaining_units"] is None
    assert response.data["expiry_date"] is None

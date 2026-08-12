from django.urls import path

from .views import (
    InventoryBatchDestroyView,
    InventoryBatchExpiryActionView,
    InventoryBatchExpiryDateCorrectionView,
    InventoryBatchListView,
    MedicineDescriptionParseView,
)


urlpatterns = [
    path(
        "inventory-batches/parse-description",
        MedicineDescriptionParseView.as_view(),
        name="inventory-batch-parse-description",
    ),
    path(
        "inventory-batches",
        InventoryBatchListView.as_view(),
        name="inventory-batch-list",
    ),
    path(
        "inventory-batches/<uuid:pk>",
        InventoryBatchDestroyView.as_view(),
        name="inventory-batch-detail",
    ),
    path(
        "inventory-batches/<uuid:pk>/expiry-actions",
        InventoryBatchExpiryActionView.as_view(),
        name="inventory-batch-expiry-actions",
    ),
    path(
        "inventory-batches/<uuid:pk>/expiry-dates",
        InventoryBatchExpiryDateCorrectionView.as_view(),
        name="inventory-batch-expiry-dates",
    ),
]

from django.urls import path

from .views import (
    InventoryBatchDestroyView,
    InventoryBatchExpiryActionView,
    InventoryBatchListView,
)


urlpatterns = [
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
]

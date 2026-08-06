from django.urls import path

from .views import InventoryBatchDestroyView, InventoryBatchListView


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
]

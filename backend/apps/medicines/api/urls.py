from django.urls import path

from .views import InventoryBatchListView


urlpatterns = [
    path(
        "inventory-batches",
        InventoryBatchListView.as_view(),
        name="inventory-batch-list",
    ),
]

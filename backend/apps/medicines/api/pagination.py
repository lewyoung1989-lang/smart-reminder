from rest_framework.pagination import CursorPagination


class InventoryBatchCursorPagination(CursorPagination):
    page_size = 50
    ordering = ("expiry_sort", "id")

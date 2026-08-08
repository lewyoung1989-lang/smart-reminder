from django.urls import path

from .views import (
    MedicationOccurrenceActionView,
    MedicationOccurrenceListView,
    MedicationPlanListCreateView,
)


urlpatterns = [
    path(
        "medication/plans",
        MedicationPlanListCreateView.as_view(),
        name="medication-plan-list",
    ),
    path(
        "medication/occurrences/<uuid:occurrence_id>/actions",
        MedicationOccurrenceActionView.as_view(),
        name="medication-occurrence-action",
    ),
    path(
        "medication/occurrences",
        MedicationOccurrenceListView.as_view(),
        name="medication-occurrence-list",
    ),
]

from django.urls import path

from .views import (
    JobConfirmView,
    JobDetailView,
    JobListCreateView,
    UploadView,
)


urlpatterns = [
    path("uploads", UploadView.as_view(), name="ocr-upload"),
    path("jobs", JobListCreateView.as_view(), name="ocr-job-list"),
    path(
        "jobs/<uuid:job_id>",
        JobDetailView.as_view(),
        name="ocr-job-detail",
    ),
    path(
        "jobs/<uuid:job_id>/confirm",
        JobConfirmView.as_view(),
        name="ocr-job-confirm",
    ),
]

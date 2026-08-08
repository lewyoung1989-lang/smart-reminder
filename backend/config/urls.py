from django.urls import include, path

from apps.core.views import health
from apps.reminders.api.views import (
    ReminderCancelView,
    ReminderDraftListCreateView,
    ReminderListView,
    VoiceReminderDraftConfirmView,
)
from apps.workflows.api.views import WorkflowDraftConfirmView, WorkflowDraftListCreateView


urlpatterns = [
    path("api/v1/health", health, name="health"),
    path(
        "api/v1/workflow-drafts",
        WorkflowDraftListCreateView.as_view(),
        name="workflow-draft-list",
    ),
    path(
        "api/v1/workflow-drafts/<uuid:draft_id>/confirm",
        WorkflowDraftConfirmView.as_view(),
        name="workflow-draft-confirm",
    ),
    path("api/v1/", include("apps.workflows.api.urls")),
    path("api/v1/auth/", include("apps.accounts.api.urls")),
    path(
        "api/v1/reminder-drafts",
        ReminderDraftListCreateView.as_view(),
        name="reminder-draft-list",
    ),
    path(
        "api/v1/reminder-drafts/<uuid:draft_id>/confirm",
        VoiceReminderDraftConfirmView.as_view(),
        name="reminder-draft-confirm",
    ),
    path("api/v1/voice/", include("apps.voice.api.urls")),
    path("api/v1/reminders", ReminderListView.as_view(), name="reminder-list"),
    path(
        "api/v1/reminders/<uuid:reminder_id>/cancel",
        ReminderCancelView.as_view(),
        name="reminder-cancel",
    ),
    path("api/v1/voice/", include("apps.reminders.api.urls")),
    path("api/v1/ocr/", include("apps.ocr.api.urls")),
    path("api/v1/", include("apps.medicines.api.urls")),
    path("api/v1/", include("apps.medication.api.urls")),
]

from django.urls import include, path

from apps.core.views import health
from apps.reminders.api.views import ReminderDraftListCreateView, VoiceReminderDraftConfirmView


urlpatterns = [
    path("api/v1/health", health, name="health"),
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
    path("api/v1/voice/", include("apps.reminders.api.urls")),
]

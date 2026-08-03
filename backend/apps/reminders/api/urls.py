from django.urls import path

from .views import VoiceReminderDraftListCreateView


urlpatterns = [
    path(
        "reminder-drafts",
        VoiceReminderDraftListCreateView.as_view(),
        name="voice-reminder-draft-list",
    ),
]

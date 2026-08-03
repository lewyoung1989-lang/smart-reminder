from django.urls import path

from .views import VoiceReminderDraftConfirmView, VoiceReminderDraftListCreateView


urlpatterns = [
    path(
        "reminder-drafts",
        VoiceReminderDraftListCreateView.as_view(),
        name="voice-reminder-draft-list",
    ),
    path(
        "reminder-drafts/<uuid:draft_id>/confirm",
        VoiceReminderDraftConfirmView.as_view(),
        name="voice-reminder-draft-confirm",
    ),
]

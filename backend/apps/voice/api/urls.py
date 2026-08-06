from django.urls import path

from .views import VoiceTranscriptionView


urlpatterns = [
    path("transcriptions", VoiceTranscriptionView.as_view(), name="transcription"),
]

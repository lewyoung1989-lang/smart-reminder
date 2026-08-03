from django.urls import include, path

from apps.core.views import health


urlpatterns = [
    path("api/v1/health", health, name="health"),
    path("api/v1/voice/", include("apps.reminders.api.urls")),
]

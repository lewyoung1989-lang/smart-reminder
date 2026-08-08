from django.urls import path

from .action import TodayActionCenterView


urlpatterns = [
    path(
        "action-center/today",
        TodayActionCenterView.as_view(),
        name="today-action-center",
    ),
]

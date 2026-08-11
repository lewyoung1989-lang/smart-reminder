from django.urls import path

from .action import TodayActionCenterView
from .plans import PlanDetailView, PlanListView


urlpatterns = [
    path(
        "action-center/today",
        TodayActionCenterView.as_view(),
        name="today-action-center",
    ),
    path("plans", PlanListView.as_view(), name="plan-list"),
    path("plans/<uuid:plan_id>", PlanDetailView.as_view(), name="plan-detail"),
]

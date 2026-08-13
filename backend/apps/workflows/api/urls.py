from django.urls import path

from .action import TodayActionCenterView
from .plans import PlanDetailView, PlanListView, PlanPauseView, PlanResumeView


urlpatterns = [
    path(
        "action-center/today",
        TodayActionCenterView.as_view(),
        name="today-action-center",
    ),
    path("plans", PlanListView.as_view(), name="plan-list"),
    path("plans/<uuid:plan_id>", PlanDetailView.as_view(), name="plan-detail"),
    path("plans/<uuid:plan_id>/pause", PlanPauseView.as_view(), name="plan-pause"),
    path("plans/<uuid:plan_id>/resume", PlanResumeView.as_view(), name="plan-resume"),
]

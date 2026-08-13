from django.urls import path

from .views import (
    CurrentFamilyView,
    FamilyInvitationView,
    FamilyMemberDetailView,
    FamilyMembershipView,
    JoinFamilyView,
    TransferFamilyAdminView,
)


urlpatterns = [
    path("families/current", CurrentFamilyView.as_view()),
    path("families/invitations", FamilyInvitationView.as_view()),
    path("families/join", JoinFamilyView.as_view()),
    path("families/membership", FamilyMembershipView.as_view()),
    path("families/transfer-admin", TransferFamilyAdminView.as_view()),
    path("families/members/<uuid:member_id>", FamilyMemberDetailView.as_view()),
]

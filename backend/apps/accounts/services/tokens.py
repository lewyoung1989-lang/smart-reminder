from django.conf import settings
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.phone import mask_phone


def user_summary(user):
    identity = user.phone_identity
    return {
        "id": str(user.id),
        "phone_masked": mask_phone(identity.phone_e164),
        "phone_verified": identity.phone_verified,
    }


def issue_tokens(user):
    refresh = RefreshToken.for_user(user)
    return {
        "access_token": str(refresh.access_token),
        "refresh_token": str(refresh),
        "access_expires_in": int(
            settings.SIMPLE_JWT["ACCESS_TOKEN_LIFETIME"].total_seconds()
        ),
    }


def authentication_payload(user):
    return {"user": user_summary(user), **issue_tokens(user)}

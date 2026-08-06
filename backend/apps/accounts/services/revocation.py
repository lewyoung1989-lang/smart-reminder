from django.utils import timezone
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)


def revoke_all_refresh_tokens(user):
    outstanding = OutstandingToken.objects.filter(
        user=user,
        expires_at__gt=timezone.now(),
    )
    for token in outstanding.iterator():
        BlacklistedToken.objects.get_or_create(token=token)

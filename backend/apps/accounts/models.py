from django.conf import settings
from django.db import models


class PhoneIdentity(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        primary_key=True,
        on_delete=models.CASCADE,
        related_name="phone_identity",
    )
    phone_e164 = models.CharField(max_length=16, unique=True, db_index=True)
    phone_verified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.phone_e164

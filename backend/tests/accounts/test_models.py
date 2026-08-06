import pytest
from django.db import IntegrityError, transaction


@pytest.mark.django_db
def test_phone_identity_is_unique(user, django_user_model):
    from apps.accounts.models import PhoneIdentity

    PhoneIdentity.objects.create(user=user, phone_e164="+8613800138000")
    other = django_user_model.objects.create_user(username="other")

    with pytest.raises(IntegrityError), transaction.atomic():
        PhoneIdentity.objects.create(
            user=other,
            phone_e164="+8613800138000",
        )


@pytest.mark.django_db
def test_phone_identity_defaults_to_unverified(user):
    from apps.accounts.models import PhoneIdentity

    identity = PhoneIdentity.objects.create(
        user=user,
        phone_e164="+8613800138000",
    )

    assert identity.phone_verified is False
    assert identity.created_at is not None
    assert identity.updated_at is not None

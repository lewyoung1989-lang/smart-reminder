import getpass

from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.accounts.models import PhoneIdentity
from apps.accounts.phone import InvalidPhone, normalize_mainland_phone
from apps.accounts.services.revocation import revoke_all_refresh_tokens


class Command(BaseCommand):
    help = "Interactively reset a phone account password and revoke sessions."

    def add_arguments(self, parser):
        parser.add_argument("phone")

    def handle(self, *args, **options):
        try:
            phone_e164 = normalize_mainland_phone(options["phone"])
        except InvalidPhone as exc:
            raise CommandError("Invalid mainland China phone number.") from exc
        try:
            user = PhoneIdentity.objects.select_related("user").get(
                phone_e164=phone_e164
            ).user
        except PhoneIdentity.DoesNotExist as exc:
            raise CommandError("Account not found.") from exc

        password = getpass.getpass("New password: ")
        confirmation = getpass.getpass("Confirm password: ")
        if password != confirmation:
            raise CommandError("Passwords do not match.")
        if len(password) > 64:
            raise CommandError("Password does not meet validation rules.")
        try:
            validate_password(password, user=user)
        except ValidationError as exc:
            raise CommandError(
                "Password does not meet validation rules."
            ) from exc

        with transaction.atomic():
            user = (
                get_user_model()
                .objects.select_for_update()
                .get(pk=user.pk)
            )
            user.set_password(password)
            user.save(update_fields=["password"])
            revoke_all_refresh_tokens(user)
        self.stdout.write(f"Password reset completed for user_id={user.pk}")

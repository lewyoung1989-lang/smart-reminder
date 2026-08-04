from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from rest_framework.authtoken.models import Token


class Command(BaseCommand):
    help = "Create or reuse a bearer token for local iPhone testing."

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError("This command requires DEBUG=True")

        user, created = get_user_model().objects.get_or_create(username="local-tester")
        if created:
            user.set_unusable_password()
            user.save(update_fields=["password"])
        token, _ = Token.objects.get_or_create(user=user)
        self.stdout.write(f"Local test token: {token.key}")

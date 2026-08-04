from io import StringIO

import pytest
from django.core.management import CommandError, call_command
from rest_framework.authtoken.models import Token


@pytest.mark.django_db
def test_command_creates_reusable_local_token(settings):
    settings.DEBUG = True
    first_output = StringIO()
    second_output = StringIO()

    call_command("create_local_test_token", stdout=first_output)
    call_command("create_local_test_token", stdout=second_output)

    token = Token.objects.get(user__username="local-tester")
    assert token.key in first_output.getvalue()
    assert token.key in second_output.getvalue()
    assert Token.objects.count() == 1


@pytest.mark.django_db
def test_command_is_disabled_outside_debug(settings):
    settings.DEBUG = False

    with pytest.raises(CommandError, match="DEBUG"):
        call_command("create_local_test_token")

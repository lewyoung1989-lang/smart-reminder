from contextlib import nullcontext

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError


class FakeCursor:
    def execute(self, query):
        assert query == "SELECT 1"

    def fetchone(self):
        return (1,)


class FakeCache:
    def __init__(self):
        self.values = {}

    def set(self, key, value, timeout):
        self.values[key] = value

    def get(self, key):
        return self.values.get(key)

    def delete(self, key):
        self.values.pop(key, None)


def test_release_dependency_check_probes_db_redis_and_funasr(mocker, capsys):
    connection = mocker.patch(
        "apps.core.management.commands.check_release_dependencies.connection"
    )
    connection.cursor.return_value = nullcontext(FakeCursor())
    cache = FakeCache()
    mocker.patch(
        "apps.core.management.commands.check_release_dependencies.cache",
        cache,
    )
    response = mocker.MagicMock()
    response.status = 200
    mocker.patch(
        "apps.core.management.commands.check_release_dependencies.urllib.request.urlopen",
        return_value=nullcontext(response),
    )

    call_command("check_release_dependencies")

    assert capsys.readouterr().out.strip() == "Release dependency preflight passed"
    assert cache.values == {}


def test_release_dependency_check_hides_dependency_errors(mocker):
    connection = mocker.patch(
        "apps.core.management.commands.check_release_dependencies.connection"
    )
    connection.cursor.side_effect = RuntimeError("secret database detail")

    with pytest.raises(CommandError) as exc_info:
        call_command("check_release_dependencies")

    assert str(exc_info.value) == "Release dependency preflight failed"
    assert "secret" not in str(exc_info.value)

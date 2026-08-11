import pytest
from django.core.exceptions import ImproperlyConfigured

from config.settings import _positive_int_setting


@pytest.mark.parametrize("value", ["0", "-1"])
def test_outbox_settings_reject_non_positive_values(value):
    with pytest.raises(ImproperlyConfigured, match="OUTBOX_LEASE_SECONDS must be positive"):
        _positive_int_setting("OUTBOX_LEASE_SECONDS", value)


def test_outbox_settings_accept_positive_values():
    assert _positive_int_setting("OUTBOX_PUBLISH_BATCH_SIZE", "1") == 1

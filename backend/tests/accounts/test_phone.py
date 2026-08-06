import pytest


def test_normalizes_mainland_phone_to_e164():
    from apps.accounts.phone import normalize_mainland_phone

    assert normalize_mainland_phone(" 13800138000 ") == "+8613800138000"


@pytest.mark.parametrize(
    "value",
    [
        "",
        "12800138000",
        "+8613800138000",
        "138-0013-8000",
        "1380013800",
        "138001380000",
    ],
)
def test_rejects_unsupported_phone_formats(value):
    from apps.accounts.phone import InvalidPhone, normalize_mainland_phone

    with pytest.raises(InvalidPhone):
        normalize_mainland_phone(value)


def test_masks_normalized_phone():
    from apps.accounts.phone import mask_phone

    assert mask_phone("+8613800138000") == "138****8000"

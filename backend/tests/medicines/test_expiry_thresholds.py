from datetime import date

from apps.medicines.services.expiry import expiry_threshold_dates


def test_expiry_threshold_dates_use_effective_deadline():
    assert expiry_threshold_dates(date(2026, 12, 31)) == [
        (90, date(2026, 10, 2)),
        (30, date(2026, 12, 1)),
        (7, date(2026, 12, 24)),
        (0, date(2026, 12, 31)),
    ]

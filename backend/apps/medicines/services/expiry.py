from datetime import date, timedelta


DEFAULT_EXPIRY_THRESHOLDS = (90, 30, 7, 0)


def expiry_threshold_dates(deadline: date) -> list[tuple[int, date]]:
    return [
        (threshold_days, deadline - timedelta(days=threshold_days))
        for threshold_days in DEFAULT_EXPIRY_THRESHOLDS
    ]

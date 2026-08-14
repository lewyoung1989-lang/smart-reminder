from datetime import datetime, time, timedelta, timezone as datetime_timezone
from zoneinfo import ZoneInfo

from apps.workflows.domain.schemas import WorkflowSpec


MAX_DAILY_MEDICATION_TIMES = 8


def medication_times_from_config(config: dict) -> list[str]:
    raw_times = config.get("times")
    if raw_times is None:
        raw_times = [config.get("time_of_day")]
    if (
        not isinstance(raw_times, list)
        or not raw_times
        or len(raw_times) > MAX_DAILY_MEDICATION_TIMES
    ):
        raise ValueError("medication workflow has invalid daily times")

    times: list[str] = []
    for value in raw_times:
        if not isinstance(value, str):
            raise ValueError("medication workflow has invalid daily times")
        try:
            parsed = time.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("medication workflow has invalid daily times") from exc
        if parsed.second or parsed.microsecond:
            raise ValueError("medication workflow has invalid daily times")
        normalized = f"{parsed.hour:02d}:{parsed.minute:02d}"
        if normalized in times:
            raise ValueError("medication workflow has duplicate daily times")
        times.append(normalized)
    return sorted(times)


def medication_times_from_workflow(workflow: WorkflowSpec) -> list[str]:
    for node in workflow.nodes:
        if (
            node.id == "medication-schedule"
            and node.type == "trigger.medication_schedule"
        ):
            return medication_times_from_config(node.config)
    raise ValueError("medication workflow is missing its schedule trigger")


def next_medication_run_at(
    *, times: list[str], timezone_name: str, after: datetime
) -> datetime:
    if after.tzinfo is None:
        raise ValueError("after must be timezone-aware")
    location = ZoneInfo(timezone_name)
    local_after = after.astimezone(location)
    parsed_times = [time.fromisoformat(value) for value in times]
    for day_offset in (0, 1):
        local_date = local_after.date() + timedelta(days=day_offset)
        for parsed_time in parsed_times:
            candidate = datetime.combine(local_date, parsed_time, tzinfo=location)
            if candidate > local_after:
                return candidate.astimezone(datetime_timezone.utc)
    raise ValueError("unable to calculate next medication run")


def next_daily_occurrences(
    *, times: list[str], timezone_name: str, after: datetime
) -> list[datetime]:
    return [
        next_medication_run_at(
            times=[time_text],
            timezone_name=timezone_name,
            after=after,
        )
        for time_text in times
    ]

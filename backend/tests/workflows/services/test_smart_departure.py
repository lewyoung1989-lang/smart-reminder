from dataclasses import dataclass
from datetime import datetime, timedelta, timezone as datetime_timezone
from zoneinfo import ZoneInfo

import pytest

from apps.workflows.domain.schemas import TaskSpec
from apps.workflows.services.compiler import WorkflowCompiler


NOW = datetime(2026, 8, 8, 9, 30, tzinfo=datetime_timezone.utc)


@dataclass(frozen=True)
class SuccessfulRouteProvider:
    def estimate(self, *, destination_text, travel_mode, arrival_time):
        return {
            "status": "available",
            "duration_minutes": 32,
            "source": "test.route",
            "navigation_url": "iosamap://path?dname=虹桥火车站",
        }


@dataclass(frozen=True)
class SuccessfulWeatherProvider:
    def forecast(self, *, destination_text, arrival_time):
        return {
            "status": "available",
            "condition": "rain",
            "precipitation_probability": 0.76,
            "source": "test.weather",
        }


class FailingProvider:
    def estimate(self, **kwargs):
        raise RuntimeError("route provider unavailable")

    def forecast(self, **kwargs):
        raise RuntimeError("weather provider unavailable")


def _workflow(arrival_time):
    return WorkflowCompiler().compile(
        TaskSpec(
            title="去虹桥火车站",
            slots={
                "arrival_time": arrival_time.isoformat(),
                "destination_text": "虹桥火车站",
                "travel_mode": "transit",
            },
        )
    )


def test_smart_departure_payload_uses_provider_results():
    from apps.workflows.services.smart_departure import build_departure_payload

    arrival_time = (NOW + timedelta(minutes=42)).astimezone(
        ZoneInfo("Asia/Shanghai")
    )

    payload = build_departure_payload(
        _workflow(arrival_time),
        route_provider=SuccessfulRouteProvider(),
        weather_provider=SuccessfulWeatherProvider(),
    )

    assert payload["route"] == {
        "status": "available",
        "duration_minutes": 32,
        "source": "test.route",
        "navigation_url": "iosamap://path?dname=虹桥火车站",
    }
    assert payload["weather"] == {
        "status": "available",
        "condition": "rain",
        "precipitation_probability": 0.76,
        "source": "test.weather",
    }
    assert payload["departure_at"] == NOW.isoformat()


def test_smart_departure_payload_degrades_without_faking_provider_data():
    from apps.workflows.services.smart_departure import build_departure_payload

    arrival_time = (NOW + timedelta(minutes=55)).astimezone(
        ZoneInfo("Asia/Shanghai")
    )

    payload = build_departure_payload(
        _workflow(arrival_time),
        route_provider=FailingProvider(),
        weather_provider=FailingProvider(),
    )

    assert payload["route"] == {
        "status": "fallback_static",
        "duration_minutes": 45,
        "source": "route.last_success_or_static",
    }
    assert payload["weather"] == {
        "status": "unavailable",
        "source": "weather.unavailable",
    }
    assert payload["departure_at"] == NOW.isoformat()

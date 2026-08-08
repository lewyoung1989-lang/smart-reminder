from __future__ import annotations

from datetime import datetime, timedelta, timezone as datetime_timezone
from typing import Protocol

from django.conf import settings
from django.utils.module_loading import import_string


STATIC_ROUTE_DURATION_MINUTES = 45
EARLY_PRECHECK_LEAD = timedelta(hours=2)
FINAL_PRECHECK_LEAD = timedelta(minutes=20)
DEPARTURE_CHANGE_THRESHOLD = timedelta(minutes=5)


class RouteProvider(Protocol):
    def estimate(self, *, destination_text, travel_mode, arrival_time): ...


class WeatherProvider(Protocol):
    def forecast(self, *, destination_text, arrival_time): ...


class UnavailableRouteProvider:
    def estimate(self, *, destination_text, travel_mode, arrival_time):
        raise RuntimeError("route provider unavailable")


class UnavailableWeatherProvider:
    def forecast(self, *, destination_text, arrival_time):
        raise RuntimeError("weather provider unavailable")


def get_route_provider():
    return _provider_from_setting(
        settings.SMART_DEPARTURE_ROUTE_PROVIDER,
        UnavailableRouteProvider,
    )


def get_weather_provider():
    return _provider_from_setting(
        settings.SMART_DEPARTURE_WEATHER_PROVIDER,
        UnavailableWeatherProvider,
    )


def build_departure_payload(
    workflow,
    *,
    route_provider: RouteProvider | None = None,
    weather_provider: WeatherProvider | None = None,
):
    trigger = _node_config(
        workflow,
        node_id="before-arrival",
        node_type="trigger.before_arrival",
    )
    route_config = _node_config(
        workflow,
        node_id="route-eta",
        node_type="source.route_eta",
    )
    arrival_time = datetime.fromisoformat(trigger["arrival_time"])
    destination_text = route_config["destination_text"]
    travel_mode = route_config["travel_mode"]
    lead_time_minutes = int(trigger["lead_time_minutes"])

    route = _route_payload(
        route_provider or UnavailableRouteProvider(),
        destination_text=destination_text,
        travel_mode=travel_mode,
        arrival_time=arrival_time,
    )
    weather = _weather_payload(
        weather_provider or UnavailableWeatherProvider(),
        destination_text=destination_text,
        arrival_time=arrival_time,
    )
    departure_at = arrival_time - timedelta(
        minutes=int(route["duration_minutes"]) + lead_time_minutes
    )
    return {
        "kind": "smart_departure",
        "arrival_time": arrival_time.isoformat(),
        "destination_text": destination_text,
        "travel_mode": travel_mode,
        "departure_at": departure_at.astimezone(datetime_timezone.utc).isoformat(),
        "route": route,
        "weather": weather,
    }


def initial_departure_run_at(workflow):
    arrival_time = _arrival_time(workflow)
    return arrival_time - EARLY_PRECHECK_LEAD


def next_departure_run_at(workflow, scheduled_for):
    _, final_check_at = departure_precheck_times(workflow)
    if scheduled_for.astimezone(datetime_timezone.utc) < final_check_at.astimezone(
        datetime_timezone.utc
    ):
        return final_check_at
    return None


def departure_precheck_times(workflow):
    arrival_time = _arrival_time(workflow)
    return arrival_time - EARLY_PRECHECK_LEAD, arrival_time - FINAL_PRECHECK_LEAD


def should_notify_departure(previous_payload, current_payload):
    if previous_payload is None:
        return True
    previous_departure = datetime.fromisoformat(previous_payload["departure_at"])
    current_departure = datetime.fromisoformat(current_payload["departure_at"])
    if abs(current_departure - previous_departure) >= DEPARTURE_CHANGE_THRESHOLD:
        return True
    return not _has_rain_risk(previous_payload) and _has_rain_risk(current_payload)


def _node_config(workflow, *, node_id, node_type):
    for node in workflow.nodes:
        if node.id == node_id and node.type == node_type:
            return node.config
    raise ValueError(f"workflow is missing {node_id}")


def _arrival_time(workflow):
    trigger = _node_config(
        workflow,
        node_id="before-arrival",
        node_type="trigger.before_arrival",
    )
    return datetime.fromisoformat(trigger["arrival_time"])


def _route_payload(provider, *, destination_text, travel_mode, arrival_time):
    try:
        payload = provider.estimate(
            destination_text=destination_text,
            travel_mode=travel_mode,
            arrival_time=arrival_time,
        )
    except Exception:
        return {
            "status": "fallback_static",
            "duration_minutes": STATIC_ROUTE_DURATION_MINUTES,
            "source": "route.last_success_or_static",
        }
    return dict(payload)


def _weather_payload(provider, *, destination_text, arrival_time):
    try:
        payload = provider.forecast(
            destination_text=destination_text,
            arrival_time=arrival_time,
        )
    except Exception:
        return {
            "status": "unavailable",
            "source": "weather.unavailable",
        }
    return dict(payload)


def _has_rain_risk(payload):
    weather = payload.get("weather") or {}
    if weather.get("status") != "available":
        return False
    condition = str(weather.get("condition", "")).lower()
    probability = weather.get("precipitation_probability")
    return "rain" in condition or (
        isinstance(probability, int | float) and probability > 0
    )


def _provider_from_setting(configured, fallback_class):
    if configured in {"", "none", None}:
        return fallback_class()
    provider = import_string(configured) if isinstance(configured, str) else configured
    return provider() if isinstance(provider, type) else provider

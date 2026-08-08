from __future__ import annotations

from datetime import datetime, timedelta, timezone as datetime_timezone
from typing import Protocol


STATIC_ROUTE_DURATION_MINUTES = 45


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


def _node_config(workflow, *, node_id, node_type):
    for node in workflow.nodes:
        if node.id == node_id and node.type == node_type:
            return node.config
    raise ValueError(f"workflow is missing {node_id}")


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

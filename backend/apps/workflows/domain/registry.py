"""Server-owned workflow template definitions."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from types import MappingProxyType
from typing import Literal, TypeAlias

from pydantic import JsonValue


FailureMode = Literal["fail", "degrade", "skip"]
FrozenJsonValue: TypeAlias = (
    None | bool | int | float | str | tuple["FrozenJsonValue", ...] | Mapping[str, "FrozenJsonValue"]
)


def _freeze_json(value: JsonValue) -> FrozenJsonValue:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze_json(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze_json(item) for item in value)
    return value


def _fixed_config(config: dict[str, JsonValue]) -> Mapping[str, FrozenJsonValue]:
    return MappingProxyType({key: _freeze_json(value) for key, value in config.items()})


@dataclass(frozen=True)
class RegisteredNode:
    id: str
    type: str
    config: Mapping[str, FrozenJsonValue]
    failure_mode: FailureMode
    fallback: str | None = None


@dataclass(frozen=True)
class SlotConfigBinding:
    slot_name: str
    node_id: str
    config_key: str


@dataclass(frozen=True)
class WorkflowTemplate:
    key: str
    version: str
    risk_level: Literal["R1", "R2"]
    required_slots: frozenset[str]
    optional_slots: frozenset[str]
    capability_manifest: frozenset[str]
    nodes: tuple[RegisteredNode, ...]
    edges: tuple[tuple[str, str], ...]
    slot_bindings: tuple[SlotConfigBinding, ...]

    @property
    def allowed_slots(self) -> frozenset[str]:
        return self.required_slots | self.optional_slots


WORKFLOW_TEMPLATES: Mapping[str, WorkflowTemplate] = MappingProxyType(
    {
        "medication_cycle": WorkflowTemplate(
            key="medication_cycle",
            version="1.0.0",
            risk_level="R2",
            required_slots=frozenset(
                {"medicine_name", "dose_text", "frequency", "time_of_day"}
            ),
            optional_slots=frozenset({"times"}),
            capability_manifest=frozenset(
                {"medicine.schedule", "notification.important"}
            ),
            nodes=(
                RegisteredNode(
                    id="medication-schedule",
                    type="trigger.medication_schedule",
                    config=_fixed_config({"schedule_policy": "medication_cycle.default"}),
                    failure_mode="fail",
                ),
                RegisteredNode(
                    id="medicine-inventory",
                    type="source.medicine_inventory",
                    config=_fixed_config({"lookup_policy": "current_inventory"}),
                    failure_mode="degrade",
                    fallback="medicine_inventory.last_known",
                ),
                RegisteredNode(
                    id="medication-status",
                    type="decision.expiry_status",
                    config=_fixed_config({"policy": "medication_due"}),
                    failure_mode="fail",
                ),
                RegisteredNode(
                    id="notify",
                    type="action.important_notification",
                    config=_fixed_config({"channel": "important_notification"}),
                    failure_mode="skip",
                ),
            ),
            edges=(
                ("medication-schedule", "medicine-inventory"),
                ("medicine-inventory", "medication-status"),
                ("medication-status", "notify"),
            ),
            slot_bindings=(
                SlotConfigBinding("medicine_name", "medication-schedule", "medicine_name"),
                SlotConfigBinding("dose_text", "medication-schedule", "dose_text"),
                SlotConfigBinding("frequency", "medication-schedule", "frequency"),
                SlotConfigBinding("time_of_day", "medication-schedule", "time_of_day"),
                SlotConfigBinding("times", "medication-schedule", "times"),
            ),
        ),
        "medicine_expiry": WorkflowTemplate(
            key="medicine_expiry",
            version="1.0.0",
            risk_level="R2",
            required_slots=frozenset({"medicine_id", "threshold_days"}),
            optional_slots=frozenset(),
            capability_manifest=frozenset(
                {"medicine.inventory", "notification.important"}
            ),
            nodes=(
                RegisteredNode(
                    id="expiry-threshold",
                    type="trigger.expiry_threshold",
                    config=_fixed_config({"threshold_policy": "medicine_expiry.default"}),
                    failure_mode="fail",
                ),
                RegisteredNode(
                    id="medicine-inventory",
                    type="source.medicine_inventory",
                    config=_fixed_config({"lookup_policy": "current_inventory"}),
                    failure_mode="degrade",
                    fallback="medicine_inventory.last_known",
                ),
                RegisteredNode(
                    id="expiry-status",
                    type="decision.expiry_status",
                    config=_fixed_config({"policy": "expiry_threshold"}),
                    failure_mode="fail",
                ),
                RegisteredNode(
                    id="notify",
                    type="action.important_notification",
                    config=_fixed_config({"channel": "important_notification"}),
                    failure_mode="skip",
                ),
            ),
            edges=(
                ("expiry-threshold", "medicine-inventory"),
                ("medicine-inventory", "expiry-status"),
                ("expiry-status", "notify"),
            ),
            slot_bindings=(
                SlotConfigBinding("medicine_id", "expiry-threshold", "medicine_id"),
                SlotConfigBinding("threshold_days", "expiry-threshold", "threshold_days"),
            ),
        ),
        "smart_departure": WorkflowTemplate(
            key="smart_departure",
            version="1.0.0",
            risk_level="R1",
            required_slots=frozenset(
                {"arrival_time", "destination_text", "travel_mode"}
            ),
            optional_slots=frozenset({"weather_advice"}),
            capability_manifest=frozenset(
                {"route.estimate", "weather.forecast", "notification.important"}
            ),
            nodes=(
                RegisteredNode(
                    id="before-arrival",
                    type="trigger.before_arrival",
                    config=_fixed_config(
                        {
                            "lead_time_policy": "smart_departure.default",
                            "lead_time_minutes": 10,
                        }
                    ),
                    failure_mode="fail",
                ),
                RegisteredNode(
                    id="route-eta",
                    type="source.route_eta",
                    config=_fixed_config(
                        {
                            "provider_policy": "managed_route",
                            "retry": {"attempts": 2, "delays_minutes": [1, 5]},
                        }
                    ),
                    failure_mode="degrade",
                    fallback="route.last_success_or_static",
                ),
                RegisteredNode(
                    id="weather",
                    type="source.weather_forecast",
                    config=_fixed_config({"provider_policy": "managed_weather"}),
                    failure_mode="degrade",
                    fallback="weather.unavailable",
                ),
                RegisteredNode(
                    id="departure-time",
                    type="decision.departure_time",
                    config=_fixed_config({"policy": "conservative_departure_time"}),
                    failure_mode="fail",
                ),
                RegisteredNode(
                    id="notify",
                    type="action.important_notification",
                    config=_fixed_config({"channel": "important_notification"}),
                    failure_mode="skip",
                ),
            ),
            edges=(
                ("before-arrival", "route-eta"),
                ("before-arrival", "weather"),
                ("route-eta", "departure-time"),
                ("weather", "departure-time"),
                ("departure-time", "notify"),
            ),
            slot_bindings=(
                SlotConfigBinding("arrival_time", "before-arrival", "arrival_time"),
                SlotConfigBinding("destination_text", "route-eta", "destination_text"),
                SlotConfigBinding("travel_mode", "route-eta", "travel_mode"),
                SlotConfigBinding("weather_advice", "weather", "advice"),
            ),
        ),
    }
)

from __future__ import annotations

import hashlib
import json
import math
import re
from collections.abc import Mapping
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, JsonValue, field_validator, model_validator


NODE_TYPES = frozenset(
    {
        "trigger.medication_schedule",
        "trigger.expiry_threshold",
        "trigger.before_arrival",
        "source.route_eta",
        "source.weather_forecast",
        "source.medicine_inventory",
        "decision.departure_time",
        "decision.expiry_status",
        "action.important_notification",
        "action.standard_notification",
        "action.open_external_app",
    }
)
TRIGGER_NODE_TYPES = frozenset(
    node_type for node_type in NODE_TYPES if node_type.startswith("trigger.")
)
ACTION_NODE_TYPES = frozenset(
    node_type for node_type in NODE_TYPES if node_type.startswith("action.")
)
FALLBACK_IDENTIFIER_PATTERN = re.compile(r"^[a-z][a-z0-9_.-]*$")
TEMPLATE_VERSION_PATTERN = re.compile(r"^[1-9][0-9]*(?:\.[0-9]+){0,2}$")


class StrictSchema(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class TaskSpec(StrictSchema):
    schema_version: Literal[1] = 1
    intent: Literal["create_workflow"] = "create_workflow"
    template_hint: str | None = None
    title: str = Field(min_length=1, max_length=200)
    slots: dict[str, JsonValue] = Field(default_factory=dict)
    requested_capabilities: list[str] = Field(default_factory=list)
    ambiguities: list[str] = Field(default_factory=list)

    @field_validator("slots", mode="before")
    @classmethod
    def slots_are_safe_json(cls, value: object) -> JsonValue:
        return _normalise_json_value(value, field_label="slots")


class FailurePolicy(StrictSchema):
    mode: Literal["fail", "degrade", "skip"]
    fallback: str | None = None

    @model_validator(mode="after")
    def validate_fallback(self) -> FailurePolicy:
        if self.mode == "degrade":
            if not self.fallback:
                raise ValueError("degrade failure policy requires a fallback identifier")
            if not FALLBACK_IDENTIFIER_PATTERN.fullmatch(self.fallback):
                raise ValueError("fallback must be a server-produced identifier")
        elif self.fallback is not None:
            raise ValueError("only degrade failure policies may define a fallback")
        return self


class WorkflowNode(StrictSchema):
    id: str = Field(min_length=1)
    type: Literal[
        "trigger.medication_schedule",
        "trigger.expiry_threshold",
        "trigger.before_arrival",
        "source.route_eta",
        "source.weather_forecast",
        "source.medicine_inventory",
        "decision.departure_time",
        "decision.expiry_status",
        "action.important_notification",
        "action.standard_notification",
        "action.open_external_app",
    ]
    config: dict[str, JsonValue] = Field(default_factory=dict)
    failure_policy: FailurePolicy

    @field_validator("id")
    @classmethod
    def id_must_contain_non_whitespace(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("node id must not be blank")
        return value

    @field_validator("config", mode="before")
    @classmethod
    def config_is_safe_json(cls, value: object) -> JsonValue:
        return _normalise_json_value(value, field_label="config")


class WorkflowSpec(StrictSchema):
    schema_version: Literal[1] = 1
    template_key: str = Field(min_length=1, max_length=128)
    template_version: str = Field(min_length=1, max_length=32)
    timezone: str = Field(min_length=1, max_length=128)
    nodes: list[WorkflowNode] = Field(min_length=1)
    edges: list[list[str]] = Field(default_factory=list)

    @field_validator("template_version")
    @classmethod
    def template_version_is_numeric(cls, value: str) -> str:
        if not TEMPLATE_VERSION_PATTERN.fullmatch(value):
            raise ValueError("template_version must begin with a numeric major version")
        return value

    @field_validator("edges")
    @classmethod
    def edges_are_id_pairs(cls, value: list[list[str]]) -> list[list[str]]:
        for edge in value:
            if len(edge) != 2:
                raise ValueError("each edge must contain exactly two node ids")
        return value

    @model_validator(mode="after")
    def validate_graph(self) -> WorkflowSpec:
        node_ids = [node.id for node in self.nodes]
        node_id_set = set(node_ids)
        if len(node_ids) != len(node_id_set):
            raise ValueError("workflow node ids must be unique")

        adjacency = {node_id: set() for node_id in node_ids}
        in_degree = {node_id: 0 for node_id in node_ids}
        for source_id, target_id in self.edges:
            if source_id not in node_id_set or target_id not in node_id_set:
                raise ValueError("edge references an unknown node")
            if source_id == target_id:
                raise ValueError("workflow edges must not be self-referential")
            if target_id not in adjacency[source_id]:
                adjacency[source_id].add(target_id)
                in_degree[target_id] += 1

        if _has_cycle(node_ids, adjacency, in_degree):
            raise ValueError("workflow graph must not contain a cycle")

        trigger_ids = [
            node.id for node in self.nodes if node.type in TRIGGER_NODE_TYPES
        ]
        if not trigger_ids:
            raise ValueError("workflow requires at least one trigger node")
        for trigger_id in trigger_ids:
            if in_degree[trigger_id] != 0:
                raise ValueError("trigger nodes must have no incoming edges")
        for node in self.nodes:
            if node.type not in TRIGGER_NODE_TYPES and in_degree[node.id] == 0:
                raise ValueError("non-trigger nodes must have an incoming edge")

        reachable = _reachable_node_ids(trigger_ids, adjacency)
        if not any(
            node.id in reachable
            and node.type in ACTION_NODE_TYPES
            and not adjacency[node.id]
            for node in self.nodes
        ):
            raise ValueError("workflow requires an action terminal reachable from a trigger")
        return self


class _SignatureScope(StrictSchema):
    scope: dict[str, JsonValue]

    @field_validator("scope", mode="before")
    @classmethod
    def scope_is_safe_json(cls, value: object) -> JsonValue:
        return _normalise_json_value(value, field_label="signature scope")


def capability_signature_payload(
    spec: WorkflowSpec,
    risk_level: str,
    scope: Mapping[str, JsonValue],
) -> dict[str, Any]:
    """Return the stable, trust-relevant subset of a compiled workflow."""
    if not isinstance(risk_level, str) or not risk_level:
        raise ValueError("risk_level must be a non-empty string")
    validated_scope = _SignatureScope.model_validate({"scope": dict(scope)}).scope

    return {
        "schema_version": spec.schema_version,
        "template_key": spec.template_key,
        "template_major_version": _template_major_version(spec.template_version),
        "node_types": sorted({node.type for node in spec.nodes}),
        "failure_policies": sorted(
            {
                (node.failure_policy.mode, node.failure_policy.fallback)
                for node in spec.nodes
            }
        ),
        "risk_level": risk_level,
        "scope": validated_scope,
    }


def capability_signature(
    spec: WorkflowSpec,
    risk_level: str,
    scope: Mapping[str, JsonValue],
) -> str:
    payload = capability_signature_payload(spec, risk_level, scope)
    encoded_payload = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded_payload.encode("utf-8")).hexdigest()


def _has_cycle(
    node_ids: list[str], adjacency: dict[str, set[str]], in_degree: dict[str, int]
) -> bool:
    remaining_in_degree = in_degree.copy()
    ready = [node_id for node_id in node_ids if remaining_in_degree[node_id] == 0]
    visited = 0
    while ready:
        node_id = ready.pop()
        visited += 1
        for target_id in adjacency[node_id]:
            remaining_in_degree[target_id] -= 1
            if remaining_in_degree[target_id] == 0:
                ready.append(target_id)
    return visited != len(node_ids)


def _reachable_node_ids(
    start_ids: list[str], adjacency: dict[str, set[str]]
) -> set[str]:
    reachable = set(start_ids)
    pending = list(start_ids)
    while pending:
        node_id = pending.pop()
        for target_id in adjacency[node_id]:
            if target_id not in reachable:
                reachable.add(target_id)
                pending.append(target_id)
    return reachable


def _template_major_version(template_version: str) -> int:
    return int(template_version.split(".", maxsplit=1)[0])


def _normalise_json_value(value: object, *, field_label: str) -> JsonValue:
    if value is None or isinstance(value, (bool, str, int)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError(f"{field_label} must contain finite JSON numbers")
        return value
    if isinstance(value, list):
        return [
            _normalise_json_value(item, field_label=field_label) for item in value
        ]
    if isinstance(value, dict):
        if not all(isinstance(key, str) for key in value):
            raise ValueError(f"{field_label} map keys must be strings")
        return {
            key: _normalise_json_value(value[key], field_label=field_label)
            for key in sorted(value)
        }
    raise ValueError(f"{field_label} must contain JSON values")

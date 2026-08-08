"""Compile untrusted task candidates into server-owned workflow graphs."""

from __future__ import annotations

from collections.abc import Mapping

from pydantic import JsonValue

from apps.workflows.domain.registry import WORKFLOW_TEMPLATES, WorkflowTemplate
from apps.workflows.domain.schemas import TaskSpec, WorkflowSpec


class WorkflowCompileError(ValueError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class WorkflowCompiler:
    """Select a fixed template from permitted slot and capability combinations."""

    def compile(self, task: TaskSpec) -> WorkflowSpec:
        slot_names = frozenset(task.slots)
        if slot_names - _all_allowed_slots() or any(
            _is_unsafe_slot_value(value) for value in task.slots.values()
        ):
            raise WorkflowCompileError("unsupported_slot")

        slot_candidates = [
            template
            for template in WORKFLOW_TEMPLATES.values()
            if template.required_slots <= slot_names
        ]
        if not slot_candidates:
            raise WorkflowCompileError("needs_clarification")

        slot_candidates = [
            template
            for template in slot_candidates
            if slot_names <= template.allowed_slots
        ]
        if not slot_candidates:
            raise WorkflowCompileError("unsupported_slot")

        requested_capabilities = frozenset(task.requested_capabilities)
        capability_candidates = [
            template
            for template in slot_candidates
            if requested_capabilities <= template.capability_manifest
        ]
        if not capability_candidates:
            raise WorkflowCompileError("unsupported_capability")
        if len(capability_candidates) != 1:
            raise WorkflowCompileError("ambiguous_template")

        return self._build_spec(capability_candidates[0], task)

    @staticmethod
    def _build_spec(template: WorkflowTemplate, task: TaskSpec) -> WorkflowSpec:
        node_configs = {
            node.id: _thaw_config(node.config) for node in template.nodes
        }
        for binding in template.slot_bindings:
            if binding.slot_name in task.slots:
                node_configs[binding.node_id][binding.config_key] = task.slots[
                    binding.slot_name
                ]

        return WorkflowSpec.model_validate(
            {
                "template_key": template.key,
                "template_version": template.version,
                "timezone": "Asia/Shanghai",
                "nodes": [
                    {
                        "id": node.id,
                        "type": node.type,
                        "config": node_configs[node.id],
                        "failure_policy": {
                            "mode": node.failure_mode,
                            **(
                                {"fallback": node.fallback}
                                if node.fallback is not None
                                else {}
                            ),
                        },
                    }
                    for node in template.nodes
                ],
                "edges": [list(edge) for edge in template.edges],
            }
        )


def _all_allowed_slots() -> frozenset[str]:
    return frozenset().union(
        *(template.allowed_slots for template in WORKFLOW_TEMPLATES.values())
    )


def _is_unsafe_slot_value(value: JsonValue) -> bool:
    if isinstance(value, str):
        return value.lower().startswith(("http://", "https://"))
    if isinstance(value, Mapping):
        return any(
            key.lower() in {"url", "callback", "expression"}
            or _is_unsafe_slot_value(item)
            for key, item in value.items()
        )
    if isinstance(value, list):
        return any(_is_unsafe_slot_value(item) for item in value)
    return False


def _thaw_config(config: Mapping[str, object]) -> dict[str, JsonValue]:
    return {key: _thaw_json(value) for key, value in config.items()}


def _thaw_json(value: object) -> JsonValue:
    if isinstance(value, Mapping):
        return {key: _thaw_json(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_thaw_json(item) for item in value]
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    raise TypeError("registered config must contain JSON values")

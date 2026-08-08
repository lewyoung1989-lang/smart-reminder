import hashlib
import json

import pytest
from pydantic import ValidationError

from apps.workflows.domain.schemas import (
    TaskSpec,
    WorkflowSpec,
    capability_signature,
    capability_signature_payload,
)


def valid_task_payload(**overrides):
    payload = {
        "schema_version": 1,
        "intent": "create_workflow",
        "template_hint": "medication_once",
        "title": "早晨服药提醒",
        "slots": {"medicine": "阿司匹林", "hour": 8},
        "requested_capabilities": ["schedule.reminder"],
        "ambiguities": [],
    }
    payload.update(overrides)
    return payload


def valid_workflow_payload(**overrides):
    payload = {
        "schema_version": 1,
        "template_key": "medication_once",
        "template_version": "1.2.3",
        "timezone": "Asia/Shanghai",
        "nodes": [
            {
                "id": "medication-trigger",
                "type": "trigger.medication_schedule",
                "config": {"schedule": "daily"},
                "failure_policy": {"mode": "fail"},
            },
            {
                "id": "notify",
                "type": "action.important_notification",
                "config": {"message": "该服药了"},
                "failure_policy": {"mode": "skip"},
            },
        ],
        "edges": [["medication-trigger", "notify"]],
    }
    payload.update(overrides)
    return payload


@pytest.mark.parametrize(
    "unknown_field, value",
    [
        ("risk_level", "high"),
        ("trust", {"preapproved": True}),
        ("components", ["notification"]),
        ("nodes", []),
        ("permission_description", "allow notifications"),
    ],
)
def test_task_spec_rejects_model_supplied_unknown_top_level_fields(
    unknown_field, value
):
    with pytest.raises(ValidationError):
        TaskSpec.model_validate(valid_task_payload(**{unknown_field: value}))


def test_task_spec_accepts_only_the_typed_candidate_shape():
    spec = TaskSpec.model_validate(valid_task_payload())

    assert spec.schema_version == 1
    assert spec.intent == "create_workflow"
    assert spec.slots == {"medicine": "阿司匹林", "hour": 8}


@pytest.mark.parametrize("non_finite_value", [float("nan"), float("inf"), float("-inf")])
def test_task_spec_rejects_non_finite_json_slot_numbers(non_finite_value):
    with pytest.raises(ValidationError, match="slots must contain finite JSON numbers"):
        TaskSpec.model_validate(
            valid_task_payload(slots={"dose": {"amount": non_finite_value}})
        )


@pytest.mark.parametrize("non_finite_value", [float("nan"), float("inf"), float("-inf")])
def test_workflow_spec_rejects_non_finite_json_config_numbers(non_finite_value):
    payload = valid_workflow_payload()
    payload["nodes"][0]["config"] = {"threshold": {"value": non_finite_value}}

    with pytest.raises(ValidationError, match="config must contain finite JSON numbers"):
        WorkflowSpec.model_validate(payload)


@pytest.mark.parametrize("non_finite_value", [float("nan"), float("inf"), float("-inf")])
def test_capability_signature_rejects_non_finite_scope_numbers(non_finite_value):
    spec = WorkflowSpec.model_validate(valid_workflow_payload())

    with pytest.raises(
        ValidationError, match="signature scope must contain finite JSON numbers"
    ):
        capability_signature(
            spec,
            risk_level="medium",
            scope={"limit": {"value": non_finite_value}},
        )


@pytest.mark.parametrize("field_name", ["slots", "config", "signature scope"])
def test_json_boundaries_reject_nested_map_keys_that_are_not_strings(field_name):
    nested_non_json_mapping = {"nested": {1: "value"}}

    if field_name == "slots":
        with pytest.raises(ValidationError, match="slots map keys must be strings"):
            TaskSpec.model_validate(valid_task_payload(slots=nested_non_json_mapping))
    elif field_name == "config":
        payload = valid_workflow_payload()
        payload["nodes"][0]["config"] = nested_non_json_mapping
        with pytest.raises(ValidationError, match="config map keys must be strings"):
            WorkflowSpec.model_validate(payload)
    else:
        spec = WorkflowSpec.model_validate(valid_workflow_payload())
        with pytest.raises(ValidationError, match="signature scope map keys must be strings"):
            capability_signature(
                spec,
                risk_level="medium",
                scope=nested_non_json_mapping,
            )


def test_json_boundaries_preserve_valid_nested_json_values():
    nested_json = {
        "when": "2026-08-08T08:00:00+08:00",
        "metadata": {"enabled": True, "attempts": [0, 1, None]},
    }
    task = TaskSpec.model_validate(valid_task_payload(slots=nested_json))
    workflow_payload = valid_workflow_payload()
    workflow_payload["nodes"][0]["config"] = nested_json
    workflow = WorkflowSpec.model_validate(workflow_payload)
    signature_payload = capability_signature_payload(
        workflow,
        risk_level="medium",
        scope=nested_json,
    )

    assert task.slots == nested_json
    assert workflow.nodes[0].config == nested_json
    assert signature_payload["scope"] == nested_json


def test_workflow_spec_rejects_a_cycle():
    payload = valid_workflow_payload(
        edges=[["medication-trigger", "notify"], ["notify", "medication-trigger"]]
    )

    with pytest.raises(ValidationError, match="cycle"):
        WorkflowSpec.model_validate(payload)


def test_workflow_spec_rejects_edges_with_unknown_nodes():
    payload = valid_workflow_payload(edges=[["medication-trigger", "missing"]])

    with pytest.raises(ValidationError, match="unknown node"):
        WorkflowSpec.model_validate(payload)


@pytest.mark.parametrize(
    "failure_policy",
    [
        {"mode": "degrade"},
        {"mode": "fail", "fallback": "retry_later"},
        {"mode": "skip", "fallback": "retry_later"},
    ],
)
def test_failure_policy_only_allows_server_fallbacks_for_degradation(failure_policy):
    payload = valid_workflow_payload(
        nodes=[
            {
                "id": "medication-trigger",
                "type": "trigger.medication_schedule",
                "config": {},
                "failure_policy": failure_policy,
            },
            *valid_workflow_payload()["nodes"][1:],
        ]
    )

    with pytest.raises(ValidationError):
        WorkflowSpec.model_validate(payload)


def test_failure_policy_accepts_a_degradation_with_a_server_identifier():
    spec = WorkflowSpec.model_validate(
        valid_workflow_payload(
            nodes=[
                {
                    "id": "medication-trigger",
                    "type": "trigger.medication_schedule",
                    "config": {},
                    "failure_policy": {
                        "mode": "degrade",
                        "fallback": "server.retry_notification",
                    },
                },
                *valid_workflow_payload()["nodes"][1:],
            ]
        )
    )

    assert spec.nodes[0].failure_policy.fallback == "server.retry_notification"


def test_workflow_spec_rejects_unknown_node_types_and_non_json_config_values():
    payload = valid_workflow_payload()
    payload["nodes"][0]["type"] = "action.model_decides"
    with pytest.raises(ValidationError):
        WorkflowSpec.model_validate(payload)

    payload = valid_workflow_payload()
    payload["nodes"][0]["config"] = {"callback": lambda: None}
    with pytest.raises(ValidationError):
        WorkflowSpec.model_validate(payload)


@pytest.mark.parametrize(
    "edges, message",
    [
        ([["medication-trigger", "medication-trigger"]], "self"),
        ([["notify", "medication-trigger"]], "trigger"),
    ],
)
def test_workflow_spec_rejects_self_edges_and_incoming_trigger_edges(edges, message):
    with pytest.raises(ValidationError, match=message):
        WorkflowSpec.model_validate(valid_workflow_payload(edges=edges))


def test_workflow_spec_rejects_non_trigger_roots_and_duplicate_node_ids():
    payload = valid_workflow_payload(edges=[])
    with pytest.raises(ValidationError, match="non-trigger"):
        WorkflowSpec.model_validate(payload)

    payload = valid_workflow_payload()
    payload["nodes"][1]["id"] = "medication-trigger"
    with pytest.raises(ValidationError, match="unique"):
        WorkflowSpec.model_validate(payload)


def test_workflow_spec_requires_an_action_terminal_reachable_from_a_trigger():
    payload = valid_workflow_payload(
        nodes=[
            {
                "id": "medication-trigger",
                "type": "trigger.medication_schedule",
                "config": {},
                "failure_policy": {"mode": "fail"},
            },
            {
                "id": "departure",
                "type": "decision.departure_time",
                "config": {},
                "failure_policy": {"mode": "fail"},
            },
        ],
        edges=[["medication-trigger", "departure"]],
    )

    with pytest.raises(ValidationError, match="action terminal"):
        WorkflowSpec.model_validate(payload)


def test_workflow_spec_accepts_a_valid_trigger_to_action_dag():
    spec = WorkflowSpec.model_validate(valid_workflow_payload())

    assert [node.id for node in spec.nodes] == ["medication-trigger", "notify"]


def test_capability_signature_is_stable_for_equivalent_key_order():
    first = WorkflowSpec.model_validate(valid_workflow_payload())
    second = WorkflowSpec.model_validate(
        {
            "edges": [["medication-trigger", "notify"]],
            "nodes": [
                {
                    "failure_policy": {"mode": "fail"},
                    "config": {"schedule": "daily"},
                    "type": "trigger.medication_schedule",
                    "id": "medication-trigger",
                },
                {
                    "id": "notify",
                    "type": "action.important_notification",
                    "config": {"message": "该服药了"},
                    "failure_policy": {"mode": "skip"},
                },
            ],
            "timezone": "Asia/Shanghai",
            "template_version": "1.2.3",
            "template_key": "medication_once",
            "schema_version": 1,
        }
    )

    assert capability_signature(first, risk_level="medium", scope={"user_id": "7"}) == (
        capability_signature(second, risk_level="medium", scope={"user_id": "7"})
    )


def test_capability_signature_ignores_titles_and_ordinary_slot_dates():
    first = WorkflowSpec.model_validate(valid_workflow_payload())
    second = WorkflowSpec.model_validate(
        valid_workflow_payload(
            nodes=[
                {
                    "id": "medication-trigger",
                    "type": "trigger.medication_schedule",
                    "config": {
                        "schedule": "2026-08-08T08:00:00+08:00",
                        "title": "早晨服药提醒",
                    },
                    "failure_policy": {"mode": "fail"},
                },
                {
                    "id": "notify",
                    "type": "action.important_notification",
                    "config": {"message": "下午再提醒一次"},
                    "failure_policy": {"mode": "skip"},
                },
            ]
        )
    )

    first_payload = capability_signature_payload(
        first, risk_level="medium", scope={"user_id": "7"}
    )
    second_payload = capability_signature_payload(
        second, risk_level="medium", scope={"user_id": "7"}
    )

    assert first_payload == second_payload
    assert capability_signature(first, risk_level="medium", scope={"user_id": "7"}) == (
        capability_signature(second, risk_level="medium", scope={"user_id": "7"})
    )


def test_capability_signature_matches_the_canonical_payload_and_hash():
    spec = WorkflowSpec.model_validate(
        {
            "schema_version": 1,
            "template_key": "medication_once",
            "template_version": "1.7.4",
            "timezone": "Asia/Shanghai",
            "nodes": [
                {
                    "id": "trigger",
                    "type": "trigger.medication_schedule",
                    "config": {"schedule": "daily"},
                    "failure_policy": {"mode": "fail"},
                },
                {
                    "id": "notify",
                    "type": "action.important_notification",
                    "config": {"message": "服药"},
                    "failure_policy": {"mode": "skip"},
                },
            ],
            "edges": [["trigger", "notify"]],
        }
    )
    scope = {
        "z_scope": {"z_key": 2, "a_key": 1},
        "a_scope": ["second", "first"],
    }
    expected_payload = {
        "schema_version": 1,
        "template_key": "medication_once",
        "template_major_version": 1,
        "node_types": [
            "action.important_notification",
            "trigger.medication_schedule",
        ],
        "failure_policies": [("fail", None), ("skip", None)],
        "risk_level": "medium",
        "scope": {
            "a_scope": ["second", "first"],
            "z_scope": {"a_key": 1, "z_key": 2},
        },
    }

    payload = capability_signature_payload(spec, risk_level="medium", scope=scope)
    expected_hash = hashlib.sha256(
        json.dumps(expected_payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()

    assert payload == expected_payload
    assert list(payload["scope"]) == ["a_scope", "z_scope"]
    assert list(payload["scope"]["z_scope"]) == ["a_key", "z_key"]
    assert capability_signature(spec, risk_level="medium", scope=scope) == expected_hash


@pytest.mark.parametrize(
    "changes",
    [
        {"template_version": "2.0.0"},
        {"risk_level": "high"},
        {"scope": {"user_id": "8"}},
    ],
)
def test_capability_signature_changes_for_template_major_risk_or_scope(changes):
    spec = WorkflowSpec.model_validate(valid_workflow_payload())
    baseline = capability_signature(spec, risk_level="medium", scope={"user_id": "7"})
    changed_spec = WorkflowSpec.model_validate(
        valid_workflow_payload(template_version=changes.get("template_version", "1.2.3"))
    )

    assert baseline != capability_signature(
        changed_spec,
        risk_level=changes.get("risk_level", "medium"),
        scope=changes.get("scope", {"user_id": "7"}),
    )

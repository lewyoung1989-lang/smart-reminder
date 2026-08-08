import pytest

from apps.workflows.domain.registry import WORKFLOW_TEMPLATES
from apps.workflows.domain.schemas import NODE_TYPES, TaskSpec
from apps.workflows.services.compiler import WorkflowCompileError, WorkflowCompiler


def task_spec(*, slots, requested_capabilities=None, template_hint=None):
    return TaskSpec(
        title="Create a reminder",
        template_hint=template_hint,
        slots=slots,
        requested_capabilities=requested_capabilities or [],
    )


def test_compiler_ignores_a_forged_template_hint_for_complete_departure_slots():
    spec = WorkflowCompiler().compile(
        task_spec(
            template_hint="medication_cycle",
            slots={
                "arrival_time": "2026-08-09T09:00:00+08:00",
                "destination_text": "Shanghai Hongqiao Railway Station",
                "travel_mode": "driving",
            },
        )
    )

    assert spec.template_key == "smart_departure"
    assert spec.template_version == "1.0.0"
    assert [(node.id, node.type) for node in spec.nodes] == [
        ("before-arrival", "trigger.before_arrival"),
        ("route-eta", "source.route_eta"),
        ("weather", "source.weather_forecast"),
        ("departure-time", "decision.departure_time"),
        ("notify", "action.important_notification"),
    ]
    assert spec.edges == [
        ["before-arrival", "route-eta"],
        ["before-arrival", "weather"],
        ["route-eta", "departure-time"],
        ["weather", "departure-time"],
        ["departure-time", "notify"],
    ]
    assert spec.nodes[1].failure_policy.model_dump() == {
        "mode": "degrade",
        "fallback": "route.last_success_or_static",
    }
    assert spec.nodes[2].failure_policy.model_dump() == {
        "mode": "degrade",
        "fallback": "weather.unavailable",
    }


def test_compiler_rejects_capabilities_outside_the_selected_manifest():
    with pytest.raises(WorkflowCompileError) as error:
        WorkflowCompiler().compile(
            task_spec(
                slots={
                    "medicine_name": "Aspirin",
                    "dose_text": "100mg",
                    "frequency": "daily",
                },
                requested_capabilities=["network.arbitrary_request"],
            )
        )

    assert error.value.code == "unsupported_capability"


@pytest.mark.parametrize(
    "slots",
    [
        {"medicine_name": "Aspirin", "dose_text": "100mg"},
        {"medicine_id": "med-1"},
        {"arrival_time": "2026-08-09T09:00:00+08:00", "travel_mode": "walking"},
    ],
)
def test_compiler_requests_clarification_when_required_slots_are_missing(slots):
    with pytest.raises(WorkflowCompileError) as error:
        WorkflowCompiler().compile(task_spec(slots=slots))

    assert error.value.code == "needs_clarification"


def test_compiler_only_emits_registered_fixed_configuration():
    spec = WorkflowCompiler().compile(
        task_spec(
            slots={
                "arrival_time": "2026-08-09T09:00:00+08:00",
                "destination_text": "Shanghai Hongqiao Railway Station",
                "travel_mode": "walking",
            },
            template_hint="arbitrary.workflow",
        )
    )

    encoded_spec = spec.model_dump_json()
    assert "callback" not in encoded_spec
    assert "expression" not in encoded_spec
    assert {node.type for node in spec.nodes}.issubset(NODE_TYPES)
    assert all(node.config for node in spec.nodes)
    assert spec.nodes[0].config["arrival_time"] == "2026-08-09T09:00:00+08:00"
    assert spec.nodes[1].config == {
        "provider_policy": "managed_route",
        "retry": {"attempts": 2, "delays_minutes": [1, 5]},
        "destination_text": "Shanghai Hongqiao Railway Station",
        "travel_mode": "walking",
    }


def test_fixed_template_registry_exposes_only_the_three_versioned_templates():
    assert set(WORKFLOW_TEMPLATES) == {
        "medication_cycle",
        "medicine_expiry",
        "smart_departure",
    }

    medication = WORKFLOW_TEMPLATES["medication_cycle"]
    expiry = WORKFLOW_TEMPLATES["medicine_expiry"]
    departure = WORKFLOW_TEMPLATES["smart_departure"]

    assert (medication.version, medication.risk_level) == ("1.0.0", "R2")
    assert (expiry.version, expiry.risk_level) == ("1.0.0", "R2")
    assert (departure.version, departure.risk_level) == ("1.0.0", "R1")
    assert medication.capability_manifest == frozenset(
        {"medicine.schedule", "notification.important"}
    )
    assert expiry.capability_manifest == frozenset(
        {"medicine.inventory", "notification.important"}
    )
    assert departure.capability_manifest == frozenset(
        {"route.estimate", "notification.important", "weather.forecast"}
    )
    assert {node.type for node in medication.nodes} == {
        "trigger.medication_schedule",
        "source.medicine_inventory",
        "decision.expiry_status",
        "action.important_notification",
    }
    assert {node.type for node in expiry.nodes} == {
        "trigger.expiry_threshold",
        "source.medicine_inventory",
        "decision.expiry_status",
        "action.important_notification",
    }
    assert {node.type for node in departure.nodes} == {
        "trigger.before_arrival",
        "source.route_eta",
        "source.weather_forecast",
        "decision.departure_time",
        "action.important_notification",
    }


def test_template_registry_is_deeply_immutable_and_compilation_copies_configs():
    template = WORKFLOW_TEMPLATES["smart_departure"]
    baseline = WorkflowCompiler().compile(
        task_spec(
            slots={
                "arrival_time": "2026-08-09T09:00:00+08:00",
                "destination_text": "Shanghai Hongqiao Railway Station",
                "travel_mode": "walking",
            }
        )
    )

    with pytest.raises(TypeError):
        WORKFLOW_TEMPLATES["new-template"] = template
    with pytest.raises(TypeError):
        template.nodes[0].config["lead_time_policy"] = "tampered"

    compiled = WorkflowCompiler().compile(
        task_spec(
            slots={
                "arrival_time": "2026-08-09T09:00:00+08:00",
                "destination_text": "Shanghai Hongqiao Railway Station",
                "travel_mode": "walking",
            }
        )
    )
    assert compiled == baseline
    assert compiled.nodes[0].config is not template.nodes[0].config
    assert template.nodes[1].config["retry"] != {"attempts": 9}
    with pytest.raises(TypeError):
        template.nodes[1].config["retry"]["attempts"] = 9


def test_compiler_thaws_nested_fixed_configs_into_json_values():
    spec = WorkflowCompiler().compile(
        task_spec(
            slots={
                "arrival_time": "2026-08-09T09:00:00+08:00",
                "destination_text": "Shanghai Hongqiao Railway Station",
                "travel_mode": "walking",
            }
        )
    )

    assert spec.nodes[1].config["retry"] == {
        "attempts": 2,
        "delays_minutes": [1, 5],
    }
    assert isinstance(spec.nodes[1].config["retry"], dict)
    assert isinstance(spec.nodes[1].config["retry"]["delays_minutes"], list)


@pytest.mark.parametrize(
    "slots, template_key, expected_config",
    [
        (
            {"medicine_name": "Aspirin", "dose_text": "100mg", "frequency": "daily"},
            "medication_cycle",
            {"medicine_name": "Aspirin", "dose_text": "100mg", "frequency": "daily"},
        ),
        (
            {"medicine_id": "med-1", "threshold_days": 30},
            "medicine_expiry",
            {"medicine_id": "med-1", "threshold_days": 30},
        ),
    ],
)
def test_compiler_maps_whitelisted_business_slots_to_fixed_node_fields(
    slots, template_key, expected_config
):
    spec = WorkflowCompiler().compile(task_spec(slots=slots))

    assert spec.template_key == template_key
    assert expected_config.items() <= spec.nodes[0].config.items()


def test_compiler_accepts_the_explicit_weather_advice_extra_slot():
    spec = WorkflowCompiler().compile(
        task_spec(
            slots={
                "arrival_time": "2026-08-09T09:00:00+08:00",
                "destination_text": "Shanghai Hongqiao Railway Station",
                "travel_mode": "walking",
                "weather_advice": "avoid rain",
            }
        )
    )

    assert spec.template_key == "smart_departure"
    assert spec.nodes[2].config["advice"] == "avoid rain"


@pytest.mark.parametrize(
    "extra_slot",
    [
        {"url": "https://evil.example"},
        {"callback": "send(data)"},
        {"expression": "__import__('os')"},
    ],
)
def test_compiler_rejects_unrecognized_sensitive_slots(extra_slot):
    slots = {
        "arrival_time": "2026-08-09T09:00:00+08:00",
        "destination_text": "Shanghai Hongqiao Railway Station",
        "travel_mode": "walking",
        **extra_slot,
    }

    with pytest.raises(WorkflowCompileError) as error:
        WorkflowCompiler().compile(task_spec(slots=slots))

    assert error.value.code == "unsupported_slot"


def test_compiler_rejects_a_url_even_when_supplied_in_a_business_slot():
    with pytest.raises(WorkflowCompileError) as error:
        WorkflowCompiler().compile(
            task_spec(
                slots={
                    "arrival_time": "2026-08-09T09:00:00+08:00",
                    "destination_text": "https://evil.example/callback",
                    "travel_mode": "walking",
                }
            )
        )

    assert error.value.code == "unsupported_slot"

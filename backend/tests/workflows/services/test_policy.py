from datetime import datetime, timedelta, timezone

import pytest

from apps.workflows.domain.schemas import TaskSpec
from apps.workflows.models import TrustGrant
from apps.workflows.services.compiler import WorkflowCompiler
from apps.workflows.services.policy import evaluate


NOW = datetime(2026, 8, 8, 8, tzinfo=timezone.utc)


def departure_task(*, ambiguities=None):
    return TaskSpec(
        title="Create a departure reminder",
        slots={
            "arrival_time": "2026-08-09T09:00:00+08:00",
            "destination_text": "Shanghai Hongqiao Railway Station",
            "travel_mode": "walking",
        },
        ambiguities=ambiguities or [],
    )


def departure_spec(task=None):
    return WorkflowCompiler().compile(task or departure_task())


def grant_for(
    user,
    task,
    spec,
    *,
    scope,
    status=TrustGrant.Status.ACTIVE,
    expires_at=NOW + timedelta(hours=1),
):
    decision = evaluate(user, task, spec, NOW, scope)
    return TrustGrant.objects.create(
        user=user,
        capability_signature=decision.capability_signature,
        template_key=spec.template_key,
        template_major_version=int(spec.template_version.split(".", 1)[0]),
        scope_json=scope,
        status=status,
        expires_at=expires_at,
    )


@pytest.mark.django_db
def test_r1_workflow_requires_confirmation_before_a_trust_grant_exists(user):
    task = departure_task()
    decision = evaluate(user, task, departure_spec(task), NOW, {"household": "primary"})

    assert decision.decision == "needs_confirmation"
    assert decision.risk_level == "R1"
    assert len(decision.capability_signature) == 64
    assert decision.trust_expiry is None


@pytest.mark.django_db
def test_active_matching_r1_trust_grant_allows_automatic_creation(user):
    task = departure_task()
    spec = departure_spec(task)
    scope = {"household": "primary"}
    grant_for(user, task, spec, scope=scope)

    decision = evaluate(user, task, spec, NOW, scope)

    assert decision.decision == "auto_create"


@pytest.mark.django_db
def test_r2_workflow_never_auto_creates_even_with_a_matching_grant(user):
    task = TaskSpec(
        title="Create medication reminder",
        slots={"medicine_name": "Aspirin", "dose_text": "100mg", "frequency": "daily"},
    )
    spec = WorkflowCompiler().compile(task)
    scope = {"household": "primary"}
    grant_for(user, task, spec, scope=scope)

    decision = evaluate(user, task, spec, NOW, scope)

    assert decision.decision == "needs_confirmation"
    assert decision.risk_level == "R2"


@pytest.mark.django_db
def test_missing_required_business_field_needs_clarification(user):
    task = departure_task()
    spec = departure_spec(task).model_copy(deep=True)
    spec.nodes[0].config.pop("arrival_time")

    decision = evaluate(user, task, spec, NOW, {"household": "primary"})

    assert decision.decision == "needs_clarification"


@pytest.mark.django_db
def test_revoked_trust_grant_cannot_auto_create(user):
    task = departure_task()
    spec = departure_spec(task)
    scope = {"household": "primary"}
    grant_for(user, task, spec, scope=scope, status=TrustGrant.Status.REVOKED)

    decision = evaluate(user, task, spec, NOW, scope)

    assert decision.decision == "needs_confirmation"


@pytest.mark.django_db
def test_scope_mismatch_cannot_auto_create(user):
    task = departure_task()
    spec = departure_spec(task)
    grant_for(user, task, spec, scope={"household": "primary"})

    decision = evaluate(user, task, spec, NOW, {"household": "secondary"})

    assert decision.decision == "needs_confirmation"


@pytest.mark.django_db
def test_third_clarification_still_does_not_create_a_workflow(user):
    task = departure_task()
    decision = evaluate(
        user,
        task,
        departure_spec(task),
        NOW,
        {"household": "primary"},
        clarification_count=3,
    )

    assert decision.decision == "needs_clarification"


@pytest.mark.django_db
@pytest.mark.parametrize("expires_at", [NOW, NOW - timedelta(seconds=1), None])
def test_expired_or_unbounded_grant_cannot_auto_create(user, expires_at):
    task = departure_task()
    spec = departure_spec(task)
    scope = {"household": "primary"}
    grant_for(user, task, spec, scope=scope, expires_at=expires_at)

    decision = evaluate(user, task, spec, NOW, scope)

    assert decision.decision == "needs_confirmation"


@pytest.mark.django_db
def test_task_ambiguity_requires_clarification_despite_an_active_grant(user):
    complete_task = departure_task()
    spec = departure_spec(complete_task)
    scope = {"household": "primary"}
    grant_for(user, complete_task, spec, scope=scope)
    ambiguous_task = departure_task(ambiguities=["Which destination?"])

    decision = evaluate(user, ambiguous_task, spec, NOW, scope)

    assert decision.decision == "needs_clarification"

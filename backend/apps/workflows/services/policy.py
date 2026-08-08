"""Evaluate whether a compiled workflow may be created without confirmation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from django.contrib.auth.models import AbstractBaseUser

from apps.workflows.domain.registry import WORKFLOW_TEMPLATES, WorkflowTemplate
from apps.workflows.domain.schemas import TaskSpec, WorkflowSpec, capability_signature
from apps.workflows.models import TrustGrant


PolicyAction = Literal["needs_clarification", "needs_confirmation", "auto_create"]


@dataclass(frozen=True)
class PolicyDecision:
    decision: PolicyAction
    risk_level: Literal["R1", "R2"]
    capability_signature: str
    trust_expiry: datetime | None
    question: str | None = None


def evaluate(
    user: AbstractBaseUser,
    task: TaskSpec,
    spec: WorkflowSpec,
    now: datetime,
    scope: dict[str, object],
    clarification_count: int = 0,
) -> PolicyDecision:
    """Return the only permitted creation path for a compiled workflow."""
    template = WORKFLOW_TEMPLATES.get(spec.template_key)
    risk_level: Literal["R1", "R2"] = (
        template.risk_level if template is not None else "R2"
    )
    signature = capability_signature(spec, risk_level, scope)

    if (
        clarification_count >= 3
        or task.ambiguities
        or template is None
        or spec.template_version != template.version
        or not _required_business_fields_are_present(spec, template)
    ):
        return PolicyDecision(
            "needs_clarification",
            risk_level,
            signature,
            None,
            "workflow_details_required",
        )

    if template.risk_level == "R2":
        return PolicyDecision("needs_confirmation", risk_level, signature, None)

    major_version = int(spec.template_version.split(".", 1)[0])
    matching_grants = TrustGrant.objects.filter(
        user=user,
        capability_signature=signature,
        template_key=template.key,
        template_major_version=major_version,
        scope_json=scope,
        status=TrustGrant.Status.ACTIVE,
    )
    for grant in matching_grants:
        expires_at = grant.expires_at
        if expires_at is not None and expires_at > now:
            return PolicyDecision("auto_create", risk_level, signature, expires_at)

    return PolicyDecision("needs_confirmation", risk_level, signature, None)


def _required_business_fields_are_present(
    spec: WorkflowSpec, template: WorkflowTemplate) -> bool:
    nodes = {node.id: node for node in spec.nodes}
    for binding in template.slot_bindings:
        if binding.slot_name not in template.required_slots:
            continue
        node = nodes.get(binding.node_id)
        if node is None or _missing_business_value(node.config.get(binding.config_key)):
            return False
    return True


def _missing_business_value(value: object) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


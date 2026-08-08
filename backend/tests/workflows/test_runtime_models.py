from datetime import timedelta

import pytest
from django.db import IntegrityError, transaction
from django.db.models.deletion import ProtectedError
from django.utils import timezone

from apps.workflows.models import NodeRun, NotificationOutbox, WorkflowRun

from .test_models import create_reminder_rule


def create_workflow_run(user, *, suffix):
    return WorkflowRun.objects.create(
        workflow=create_reminder_rule(user, suffix=suffix),
        idempotency_key=f"run-{suffix}",
        result_json={},
    )


@pytest.mark.django_db
def test_outbox_owner_is_derived_from_the_workflow_run(django_user_model):
    first_user = django_user_model.objects.create_user(
        username="runtime-first", password="test-password"
    )
    second_user = django_user_model.objects.create_user(
        username="runtime-second", password="test-password"
    )
    first_run = create_workflow_run(first_user, suffix="first")
    second_run = create_workflow_run(second_user, suffix="second")

    NodeRun.objects.create(workflow_run=first_run, node_id="notify", attempt=1)
    NodeRun.objects.create(workflow_run=second_run, node_id="notify", attempt=1)
    NotificationOutbox.objects.create(
        workflow_run=first_run,
        node_id="notify",
        kind="push",
        payload_json={},
        idempotency_key="outbox-first",
    )
    NotificationOutbox.objects.create(
        workflow_run=second_run,
        node_id="notify",
        kind="push",
        payload_json={},
        idempotency_key="outbox-second",
    )

    assert "owner" not in {field.name for field in NotificationOutbox._meta.fields}
    assert NotificationOutbox.objects.filter(
        workflow_run__workflow__owner=first_user
    ).count() == 1
    assert first_run.notification_outbox_entries.get().workflow_run.workflow.owner == first_user


@pytest.mark.django_db
def test_node_run_is_unique_per_run_node_and_attempt(user):
    run = create_workflow_run(user, suffix="node-unique")
    NodeRun.objects.create(workflow_run=run, node_id="notify", attempt=1)

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NodeRun.objects.create(workflow_run=run, node_id="notify", attempt=1)

    retry = NodeRun.objects.create(workflow_run=run, node_id="notify", attempt=2)
    assert retry.attempt == 2


@pytest.mark.django_db
def test_node_run_attempt_must_be_positive(user):
    run = create_workflow_run(user, suffix="node-attempt")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NodeRun.objects.create(workflow_run=run, node_id="notify", attempt=0)


@pytest.mark.django_db
def test_notification_outbox_idempotency_key_is_globally_unique(user):
    run = create_workflow_run(user, suffix="outbox-unique")
    NotificationOutbox.objects.create(
        workflow_run=run,
        node_id="notify",
        kind="push",
        payload_json={},
        idempotency_key="notification-001",
    )

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify-retry",
                kind="push",
                payload_json={},
                idempotency_key="notification-001",
            )


@pytest.mark.django_db
def test_runtime_statuses_default_to_pending(user):
    run = create_workflow_run(user, suffix="defaults")
    node_run = NodeRun.objects.create(workflow_run=run, node_id="notify", attempt=1)
    outbox = NotificationOutbox.objects.create(
        workflow_run=run,
        node_id="notify",
        kind="push",
        payload_json={},
        idempotency_key="notification-defaults",
    )

    assert node_run.status == NodeRun.Status.PENDING
    assert outbox.status == NotificationOutbox.Status.PENDING
    assert outbox.attempts == 0
    assert outbox.published_at is None
    assert outbox.claimed_at is None
    assert outbox.claim_token is None
    assert outbox.lease_expires_at is None
    assert outbox.next_attempt_at is None
    assert outbox.last_error == ""


@pytest.mark.django_db
def test_runtime_statuses_are_restricted_to_the_outbox_lifecycle(user):
    run = create_workflow_run(user, suffix="status")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NodeRun.objects.create(
                workflow_run=run,
                node_id="notify",
                attempt=1,
                status="running",
            )

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify",
                kind="push",
                payload_json={},
                idempotency_key="notification-invalid-status",
                status="running",
            )


@pytest.mark.django_db
def test_notification_outbox_idempotency_key_must_not_be_empty(user):
    run = create_workflow_run(user, suffix="empty-key")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify",
                kind="push",
                payload_json={},
                idempotency_key="",
            )


@pytest.mark.django_db
def test_workflow_run_idempotency_key_must_not_be_empty(user):
    rule = create_reminder_rule(user, suffix="run-empty-key")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            WorkflowRun.objects.create(
                workflow=rule,
                idempotency_key="",
                result_json={},
            )


@pytest.mark.django_db
def test_claimed_outbox_requires_a_complete_lease(user):
    run = create_workflow_run(user, suffix="incomplete-lease")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify",
                kind="push",
                payload_json={},
                idempotency_key="incomplete-lease",
                status=NotificationOutbox.Status.CLAIMED,
            )


@pytest.mark.django_db
def test_non_claimed_outbox_cannot_retain_lease_fields(user):
    run = create_workflow_run(user, suffix="stale-lease")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify",
                kind="push",
                payload_json={},
                idempotency_key="stale-lease",
                claimed_at=timezone.now(),
                claim_token="dcda9bbe-b99f-4e9a-b45f-64f5945d3e51",
                lease_expires_at=timezone.now(),
            )


@pytest.mark.django_db
def test_sent_outbox_requires_published_at(user):
    run = create_workflow_run(user, suffix="unpublished-sent")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify",
                kind="push",
                payload_json={},
                idempotency_key="unpublished-sent",
                status=NotificationOutbox.Status.SENT,
            )


@pytest.mark.django_db
@pytest.mark.parametrize("offset", [timedelta(), -timedelta(seconds=1)])
def test_claimed_outbox_lease_must_expire_after_claim(user, offset):
    run = create_workflow_run(user, suffix="lease-order")
    claimed_at = timezone.now()

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify",
                kind="push",
                payload_json={},
                idempotency_key=f"lease-order-{offset.total_seconds()}",
                status=NotificationOutbox.Status.CLAIMED,
                claimed_at=claimed_at,
                claim_token="dcda9bbe-b99f-4e9a-b45f-64f5945d3e51",
                lease_expires_at=claimed_at + offset,
            )


@pytest.mark.django_db
@pytest.mark.parametrize(
    "status",
    [NotificationOutbox.Status.PENDING, NotificationOutbox.Status.FAILED],
)
def test_only_sent_outbox_can_have_published_at(user, status):
    run = create_workflow_run(user, suffix=f"published-{status}")

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            NotificationOutbox.objects.create(
                workflow_run=run,
                node_id="notify",
                kind="push",
                payload_json={},
                idempotency_key=f"published-{status}",
                status=status,
                published_at=timezone.now(),
            )


@pytest.mark.django_db
@pytest.mark.parametrize("target", ["workflow", "owner"])
def test_workflow_audit_outbox_protects_rule_and_owner_deletion(user, target):
    run = create_workflow_run(user, suffix="deletion")
    NotificationOutbox.objects.create(
        workflow_run=run,
        node_id="notify",
        kind="push",
        payload_json={"title": "Take medicine"},
        idempotency_key="notification-deletion",
    )

    with pytest.raises(ProtectedError):
        if target == "workflow":
            run.workflow.delete()
        else:
            user.delete()

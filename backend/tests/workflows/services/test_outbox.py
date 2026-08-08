from datetime import datetime, timedelta, timezone as datetime_timezone
from unittest.mock import call

import pytest

from apps.workflows.models import NotificationOutbox

from ..test_runtime_models import create_workflow_run


NOW = datetime(2099, 8, 8, 9, 30, tzinfo=datetime_timezone.utc)


class RecordingPublisher:
    def __init__(self):
        self.published = []

    def publish(self, payload, *, idempotency_key):
        self.published.append((payload, idempotency_key))


def create_outbox(user, *, suffix, **overrides):
    run = create_workflow_run(user, suffix=f"outbox-{suffix}")
    values = {
        "workflow_run": run,
        "node_id": "notify",
        "kind": "notification",
        "payload_json": {"title": "Take medicine"},
        "idempotency_key": f"outbox-publisher-{suffix}",
    }
    values.update(overrides)
    return NotificationOutbox.objects.create(**values)


@pytest.mark.django_db
def test_concurrent_workers_do_not_claim_the_same_pending_outbox(user, mocker):
    from apps.workflows.services.outbox import claim_pending_outbox

    outbox = create_outbox(user, suffix="no-duplicate")
    locked = mocker.patch.object(
        NotificationOutbox.objects,
        "select_for_update",
        wraps=NotificationOutbox.objects.select_for_update,
    )

    first_claim = claim_pending_outbox(NOW, batch=1, lease=timedelta(minutes=1))
    second_claim = claim_pending_outbox(NOW, batch=1, lease=timedelta(minutes=1))

    assert [claim.id for claim in first_claim] == [outbox.id]
    assert second_claim == []
    outbox.refresh_from_db()
    assert outbox.status == NotificationOutbox.Status.CLAIMED
    assert outbox.attempts == 1
    assert outbox.claim_token == first_claim[0].claim_token
    assert outbox.lease_expires_at == NOW + timedelta(minutes=1)
    assert locked.call_args_list == [call(skip_locked=True)] * 2


@pytest.mark.django_db
def test_claiming_recovers_an_expired_lease_with_a_new_token(user):
    from apps.workflows.services.outbox import claim_pending_outbox

    token = "dcda9bbe-b99f-4e9a-b45f-64f5945d3e51"
    outbox = create_outbox(
        user,
        suffix="expired-lease",
        status=NotificationOutbox.Status.CLAIMED,
        claimed_at=NOW - timedelta(minutes=2),
        claim_token=token,
        lease_expires_at=NOW - timedelta(minutes=1),
        attempts=1,
    )

    claims = claim_pending_outbox(NOW, batch=1, lease=timedelta(minutes=1))

    assert [claim.id for claim in claims] == [outbox.id]
    claim = claims[0]
    assert claim.claim_token != token
    assert claim.claimed_at == NOW
    assert claim.lease_expires_at == NOW + timedelta(minutes=1)
    assert claim.attempts == 2


@pytest.mark.django_db
def test_publish_marks_a_claim_as_sent_and_clears_its_lease(user):
    from apps.workflows.services.outbox import publish_pending_outbox

    outbox = create_outbox(user, suffix="sent")
    publisher = RecordingPublisher()

    delivered = publish_pending_outbox(
        NOW,
        publisher=publisher,
        batch_size=1,
        lease=timedelta(minutes=1),
    )

    assert delivered == [outbox.id]
    assert publisher.published == [(outbox.payload_json, outbox.idempotency_key)]
    outbox.refresh_from_db()
    assert outbox.status == NotificationOutbox.Status.SENT
    assert outbox.published_at >= NOW
    assert outbox.claimed_at is None
    assert outbox.claim_token is None
    assert outbox.lease_expires_at is None

    assert publish_pending_outbox(NOW, publisher=publisher, batch_size=1) == []
    assert publisher.published == [(outbox.payload_json, outbox.idempotency_key)]


@pytest.mark.django_db
def test_marking_a_claim_sent_clears_a_stale_retry_time(user):
    from apps.workflows.services.outbox import _mark_sent, claim_pending_outbox

    outbox = create_outbox(user, suffix="clear-retry")
    claim = claim_pending_outbox(NOW, batch=1, lease=timedelta(minutes=1))[0]
    NotificationOutbox.objects.filter(id=outbox.id).update(
        next_attempt_at=NOW + timedelta(minutes=5)
    )

    assert _mark_sent(claim, NOW) is True

    outbox.refresh_from_db()
    assert outbox.status == NotificationOutbox.Status.SENT
    assert outbox.next_attempt_at is None


@pytest.mark.django_db
def test_publisher_failure_returns_claim_to_pending_with_bounded_retry(user):
    from apps.workflows.services.outbox import MAX_RETRY_DELAY, publish_pending_outbox

    outbox = create_outbox(user, suffix="failure", attempts=999)

    class FailingPublisher:
        def publish(self, payload, *, idempotency_key):
            raise RuntimeError("delivery unavailable")

    assert publish_pending_outbox(NOW, FailingPublisher(), batch_size=1) == []

    outbox.refresh_from_db()
    assert outbox.status == NotificationOutbox.Status.PENDING
    assert outbox.next_attempt_at == NOW + MAX_RETRY_DELAY
    assert outbox.last_error == "delivery unavailable"
    assert outbox.claimed_at is None
    assert outbox.claim_token is None
    assert outbox.lease_expires_at is None


@pytest.mark.django_db
def test_enqueue_task_uses_service_with_the_requested_outbox_only(user, mocker):
    from apps.workflows.tasks import enqueue_outbox

    outbox = create_outbox(user, suffix="task")
    publish = mocker.patch(
        "apps.workflows.tasks.publish_pending_outbox", return_value=[outbox.id]
    )

    assert enqueue_outbox.run(str(outbox.id)) == [str(outbox.id)]

    assert publish.call_args.kwargs["outbox_id"] == outbox.id


@pytest.mark.django_db
def test_periodic_task_publishes_an_outbox_after_its_retry_time(user, settings):
    from apps.workflows.services.outbox import publish_pending_outbox
    from apps.workflows.tasks import publish_due_outbox_task

    outbox = create_outbox(user, suffix="periodic-retry")

    class FailingPublisher:
        def publish(self, payload, *, idempotency_key):
            raise RuntimeError("temporary outage")

    assert publish_pending_outbox(NOW, FailingPublisher(), batch_size=1) == []
    outbox.refresh_from_db()
    retry_at = outbox.next_attempt_at

    publisher = RecordingPublisher()
    settings.NOTIFICATION_PUBLISHER = publisher

    assert publish_due_outbox_task.run(retry_at.isoformat(), batch_size=1) == [
        str(outbox.id)
    ]
    assert publisher.published == [(outbox.payload_json, outbox.idempotency_key)]
    outbox.refresh_from_db()
    assert outbox.status == NotificationOutbox.Status.SENT


@pytest.mark.django_db
def test_expired_lease_cannot_mark_an_old_claim_sent(user, mocker):
    from apps.workflows.services.outbox import publish_pending_outbox

    outbox = create_outbox(user, suffix="lease-race")
    publisher = RecordingPublisher()
    mocker.patch(
        "apps.workflows.services.outbox.timezone.now",
        return_value=NOW + timedelta(minutes=2),
    )

    assert publish_pending_outbox(
        NOW,
        publisher,
        batch_size=1,
        lease=timedelta(minutes=1),
    ) == []
    assert publisher.published == [(outbox.payload_json, outbox.idempotency_key)]
    outbox.refresh_from_db()
    assert outbox.status == NotificationOutbox.Status.CLAIMED
    assert outbox.published_at is None

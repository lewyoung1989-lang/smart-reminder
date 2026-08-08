"""Claim and publish durable notification outbox entries."""

from datetime import timedelta
from typing import Protocol
from uuid import uuid4

from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from django.utils.module_loading import import_string

from apps.workflows.models import NotificationOutbox


MAX_RETRY_DELAY = timedelta(minutes=15)


class NotificationPublisher(Protocol):
    """Delivery adapters must make the outbox key their provider idempotency key."""

    def publish(self, payload, *, idempotency_key): ...


class InAppNotificationPublisher:
    """Deterministic default: record a successful in-app handoff without I/O."""

    def publish(self, payload, *, idempotency_key):
        return None


def get_notification_publisher() -> NotificationPublisher:
    configured = settings.NOTIFICATION_PUBLISHER
    publisher = import_string(configured) if isinstance(configured, str) else configured
    if isinstance(publisher, type):
        publisher = publisher()
    if not callable(getattr(publisher, "publish", None)):
        raise TypeError("NOTIFICATION_PUBLISHER must provide publish(payload, idempotency_key=)")
    return publisher


def _retry_delay(attempts):
    # Capping the exponent prevents a malformed attempt count from allocating a huge int.
    return min(timedelta(seconds=2 ** min(attempts, 14)), MAX_RETRY_DELAY)


def claim_pending_outbox(now, batch, lease, *, outbox_id=None):
    """Atomically lease due entries so concurrent workers cannot publish twice."""
    due = Q(
        status=NotificationOutbox.Status.PENDING,
    ) & (Q(next_attempt_at__isnull=True) | Q(next_attempt_at__lte=now))
    expired = Q(
        status=NotificationOutbox.Status.CLAIMED,
        lease_expires_at__lte=now,
    )

    with transaction.atomic():
        entries = NotificationOutbox.objects.select_for_update(skip_locked=True).filter(
            due | expired
        )
        if outbox_id is not None:
            entries = entries.filter(id=outbox_id)
        entries = list(entries.order_by("created_at", "id")[:batch])

        for entry in entries:
            entry.status = NotificationOutbox.Status.CLAIMED
            entry.claimed_at = now
            entry.claim_token = uuid4()
            entry.lease_expires_at = now + lease
            entry.attempts += 1
            entry.save(
                update_fields=[
                    "status",
                    "claimed_at",
                    "claim_token",
                    "lease_expires_at",
                    "attempts",
                ]
            )

    return entries


def _mark_sent(entry, now):
    with transaction.atomic():
        updated = NotificationOutbox.objects.filter(
            id=entry.id,
            status=NotificationOutbox.Status.CLAIMED,
            claim_token=entry.claim_token,
            lease_expires_at__gt=now,
        ).update(
            status=NotificationOutbox.Status.SENT,
            published_at=now,
            claimed_at=None,
            claim_token=None,
            lease_expires_at=None,
            next_attempt_at=None,
            last_error="",
        )
    return bool(updated)


def _renew_lease(entry, now, lease):
    updated = NotificationOutbox.objects.filter(
        id=entry.id,
        status=NotificationOutbox.Status.CLAIMED,
        claim_token=entry.claim_token,
        lease_expires_at__gt=now,
    ).update(lease_expires_at=now + lease)
    if updated:
        entry.lease_expires_at = now + lease
    return bool(updated)


def _mark_failed(entry, now, error):
    with transaction.atomic():
        NotificationOutbox.objects.filter(
            id=entry.id,
            status=NotificationOutbox.Status.CLAIMED,
            claim_token=entry.claim_token,
        ).update(
            status=NotificationOutbox.Status.PENDING,
            next_attempt_at=now + _retry_delay(entry.attempts),
            claimed_at=None,
            claim_token=None,
            lease_expires_at=None,
            last_error=str(error),
        )


def publish_pending_outbox(
    now,
    publisher,
    *,
    batch_size=100,
    lease=timedelta(minutes=1),
    outbox_id=None,
):
    """Publish currently claimable entries using the injected delivery adapter."""
    delivered = []
    for entry in claim_pending_outbox(
        now,
        batch_size,
        lease,
        outbox_id=outbox_id,
    ):
        if not _renew_lease(entry, now, lease):
            continue
        try:
            publisher.publish(entry.payload_json, idempotency_key=entry.idempotency_key)
        except Exception as error:
            _mark_failed(entry, now, error)
        else:
            completed_at = max(now, timezone.now())
            if _renew_lease(entry, completed_at, lease) and _mark_sent(
                entry, completed_at
            ):
                delivered.append(entry.id)
    return delivered

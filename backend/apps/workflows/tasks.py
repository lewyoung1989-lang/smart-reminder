from datetime import datetime, timedelta

from celery import shared_task
from django.conf import settings
from django.utils import timezone

from apps.workflows.services.dispatcher import dispatch_due_workflows
from apps.workflows.services.outbox import (
    get_notification_publisher,
    publish_pending_outbox,
)


@shared_task(acks_late=True)
def dispatch_due_workflows_task(now_iso=None, *, batch_size=100):
    now = datetime.fromisoformat(now_iso) if now_iso else timezone.now()
    return dispatch_due_workflows(now, batch_size=batch_size)


@shared_task(acks_late=True)
def enqueue_outbox(outbox_id):
    """Claim and deliver one durable outbox entry through the configured adapter."""
    from uuid import UUID

    return _publish_outbox(timezone.now(), batch_size=1, outbox_id=UUID(str(outbox_id)))


@shared_task(acks_late=True)
def publish_due_outbox_task(now_iso=None, *, batch_size=None):
    now = datetime.fromisoformat(now_iso) if now_iso else timezone.now()
    return _publish_outbox(now, batch_size=batch_size)


def _publish_outbox(now, *, batch_size=None, outbox_id=None):
    return [
        str(delivered_id)
        for delivered_id in publish_pending_outbox(
            now,
            publisher=get_notification_publisher(),
            batch_size=(batch_size or settings.OUTBOX_PUBLISH_BATCH_SIZE),
            lease=timedelta(seconds=settings.OUTBOX_LEASE_SECONDS),
            outbox_id=outbox_id,
        )
    ]

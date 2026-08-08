from datetime import datetime

from celery import shared_task
from django.utils import timezone

from apps.workflows.services.dispatcher import dispatch_due_workflows


@shared_task(acks_late=True)
def dispatch_due_workflows_task(now_iso=None, *, batch_size=100):
    now = datetime.fromisoformat(now_iso) if now_iso else timezone.now()
    return dispatch_due_workflows(now, batch_size=batch_size)


@shared_task(acks_late=True)
def enqueue_outbox(outbox_id):
    """Outbox delivery is intentionally deferred to the notification worker."""
    return None

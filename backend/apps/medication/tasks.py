from datetime import datetime

from celery import shared_task
from django.utils import timezone

from apps.medication.services.occurrences import materialize_enabled_plans


@shared_task(acks_late=True)
def materialize_medication_occurrences_task(now_iso=None, *, batch_size=100):
    now = datetime.fromisoformat(now_iso) if now_iso else timezone.now()
    return [
        str(plan.id)
        for plan in materialize_enabled_plans(now=now, batch_size=batch_size)
    ]

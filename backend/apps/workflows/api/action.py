from zoneinfo import ZoneInfo

from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.medication.models import MedicationOccurrence
from apps.reminders.models import ReminderRule
from apps.workflows.models import NotificationOutbox


LOCAL_TIMEZONE = ZoneInfo("Asia/Shanghai")
DEFAULT_LIMIT = 50
MAX_LIMIT = 50


def _as_local_iso(value):
    return value.astimezone(LOCAL_TIMEZONE).isoformat() if value is not None else None


def _pagination(request):
    values = {}
    for name, default in (("offset", 0), ("limit", DEFAULT_LIMIT)):
        raw_value = request.query_params.get(name, str(default))
        try:
            values[name] = int(raw_value)
        except ValueError as exc:
            raise ValidationError({name: "必须是整数"}) from exc
    if values["offset"] < 0:
        raise ValidationError({"offset": "必须是非负整数"})
    if not 1 <= values["limit"] <= MAX_LIMIT:
        raise ValidationError({"limit": f"必须介于 1 和 {MAX_LIMIT} 之间"})
    return values["offset"], values["limit"]


def _paginate_window(items, *, request, offset, limit):
    page = items[offset : offset + limit]
    next_url = None
    if len(items) > offset + limit:
        query = request.query_params.copy()
        query["offset"] = offset + limit
        query["limit"] = limit
        next_url = request.build_absolute_uri(f"{request.path}?{query.urlencode()}")
    return {"next": next_url, "results": page}


class TodayActionCenterView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        offset, limit = _pagination(request)
        window = offset + limit + 1
        now = timezone.now()
        failed_outbox = NotificationOutbox.objects.filter(
            workflow_run__workflow__owner=request.user,
            status=NotificationOutbox.Status.FAILED,
        ).select_related("workflow_run__workflow")
        paused_rules = ReminderRule.objects.filter(
            owner=request.user,
            template_key__isnull=False,
            enabled=False,
            paused_reason__isnull=False,
        )
        due_outbox = NotificationOutbox.objects.filter(
            workflow_run__workflow__owner=request.user,
            status=NotificationOutbox.Status.PENDING,
        ).filter(Q(next_attempt_at__isnull=True) | Q(next_attempt_at__lte=now)).select_related(
            "workflow_run__workflow"
        )
        upcoming_rules = ReminderRule.objects.filter(
            owner=request.user,
            template_key__isnull=False,
            enabled=True,
            next_run_at__gt=now,
        )
        due_medication = MedicationOccurrence.objects.filter(
            plan__owner=request.user,
            plan__enabled=True,
            status=MedicationOccurrence.Status.PENDING,
            scheduled_at__lte=now,
        ).select_related("plan__medicine")
        upcoming_medication = MedicationOccurrence.objects.filter(
            plan__owner=request.user,
            plan__enabled=True,
            status=MedicationOccurrence.Status.PENDING,
            scheduled_at__gt=now,
        ).select_related("plan__medicine")

        need_decision = [
            {
                "id": str(outbox.id),
                "title": outbox.workflow_run.workflow.title,
                "kind": "delivery",
                "status": "failed",
                "occurred_at": _as_local_iso(outbox.created_at),
            }
            for outbox in failed_outbox.order_by("-created_at", "-id")[:window]
        ]
        need_decision.extend(
            {
                "id": str(rule.id),
                "title": rule.title,
                "kind": "workflow",
                "status": "paused",
                "occurred_at": _as_local_iso(rule.next_run_at),
            }
            for rule in paused_rules.order_by("next_run_at", "id")[:window]
        )
        need_decision.extend(
            {
                "id": str(occurrence.id),
                "title": _medication_title(occurrence),
                "kind": "medication",
                "status": "due",
                "occurred_at": _as_local_iso(occurrence.scheduled_at),
            }
            for occurrence in due_medication.order_by("scheduled_at", "id")[:window]
        )

        upcoming = [
            (
                outbox.next_attempt_at or outbox.created_at,
                str(outbox.id),
                {
                    "id": str(outbox.id),
                    "title": outbox.workflow_run.workflow.title,
                    "kind": "delivery",
                    "status": "pending",
                    "occurred_at": _as_local_iso(outbox.next_attempt_at),
                },
            )
            for outbox in due_outbox.order_by("next_attempt_at", "id")[:window]
        ]
        upcoming.extend(
            (
                rule.next_run_at,
                str(rule.id),
                {
                    "id": str(rule.id),
                    "title": rule.title,
                    "kind": "workflow",
                    "status": "scheduled",
                    "occurred_at": _as_local_iso(rule.next_run_at),
                },
            )
            for rule in upcoming_rules.order_by("next_run_at", "id")[:window]
        )
        upcoming.extend(
            (
                occurrence.scheduled_at,
                str(occurrence.id),
                {
                    "id": str(occurrence.id),
                    "title": _medication_title(occurrence),
                    "kind": "medication",
                    "status": "scheduled",
                    "occurred_at": _as_local_iso(occurrence.scheduled_at),
                },
            )
            for occurrence in upcoming_medication.order_by("scheduled_at", "id")[:window]
        )
        upcoming.sort(key=lambda item: (item[0], item[1]))

        return Response(
            {
                "need_decision": _paginate_window(
                    need_decision, request=request, offset=offset, limit=limit
                ),
                "upcoming": _paginate_window(
                    [item[2] for item in upcoming],
                    request=request,
                    offset=offset,
                    limit=limit,
                ),
            }
        )


def _medication_title(occurrence):
    return f"服用{occurrence.plan.medicine.name}（{occurrence.plan.dosage_text}）"

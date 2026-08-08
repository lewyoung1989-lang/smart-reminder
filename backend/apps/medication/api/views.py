from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.medication.models import IntakeEvent, MedicationOccurrence, MedicationPlan
from apps.medication.services.occurrences import materialize_occurrences
from apps.medicines.models import MedicineItem
from apps.workflows.models import WorkflowDraft

from .serializers import (
    CreateMedicationPlanSerializer,
    MedicationOccurrenceActionSerializer,
)


def _plan_payload(plan: MedicationPlan) -> dict:
    return {
        "id": str(plan.id),
        "medicine_id": str(plan.medicine_id),
        "dosage_text": plan.dosage_text,
        "timezone": plan.timezone,
        "times": plan.schedule_json["times"],
        "enabled": plan.enabled,
    }


class MedicationPlanListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CreateMedicationPlanSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        with transaction.atomic():
            draft_id = data.get("workflow_draft_id")
            draft = None
            if draft_id is not None:
                draft = WorkflowDraft.objects.filter(
                    id=draft_id,
                    user=request.user,
                    status=WorkflowDraft.Status.CONFIRMED,
                ).first()
            if (
                draft is None
                or draft.workflow_spec_json.get("template_key") != "medication_cycle"
                or MedicationPlan.objects.filter(source_workflow_draft=draft).exists()
            ):
                raise ValidationError(
                    {"workflow_draft_id": ["需要已确认的周期用药工作流。"]}
                )
            medicine = MedicineItem.objects.filter(
                id=data["medicine_id"], owner=request.user
            ).first()
            if medicine is None:
                raise ValidationError({"medicine_id": ["药品不存在或不属于当前用户。"]})
            plan = MedicationPlan(
                owner=request.user,
                medicine=medicine,
                source_workflow_draft=draft,
                dosage_text=data["dosage_text"],
                timezone=data["timezone"],
                schedule_json={"times": data["times"]},
            )
            plan.full_clean()
            plan.save()
            materialize_occurrences(plan, now=timezone.now())
        return Response(_plan_payload(plan), status=status.HTTP_201_CREATED)


class MedicationOccurrenceActionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, occurrence_id):
        serializer = MedicationOccurrenceActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data["action"]
        with transaction.atomic():
            try:
                occurrence = (
                    MedicationOccurrence.objects.select_for_update()
                    .select_related("plan")
                    .get(id=occurrence_id, plan__owner=request.user)
                )
            except MedicationOccurrence.DoesNotExist:
                return Response(
                    {"detail": "未找到用药实例"}, status=status.HTTP_404_NOT_FOUND
                )

            if occurrence.status == MedicationOccurrence.Status.PENDING:
                occurrence.status = action
                occurrence.acted_at = timezone.now()
                occurrence.save(update_fields=["status", "acted_at"])
                event = IntakeEvent(
                    occurrence=occurrence,
                    user=request.user,
                    action=action,
                )
                event.full_clean()
                event.save()
            elif occurrence.status != action:
                return Response(
                    {"code": "medication_occurrence_already_actioned"},
                    status=status.HTTP_409_CONFLICT,
                )

        return Response(_occurrence_payload(occurrence), status=status.HTTP_200_OK)


class MedicationOccurrenceListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        occurrences = (
            MedicationOccurrence.objects.filter(
                plan__owner=request.user,
                status=MedicationOccurrence.Status.PENDING,
            )
            .select_related("plan")
            .order_by("scheduled_at", "id")[:50]
        )
        return Response({"results": [_occurrence_payload(item) for item in occurrences]})


def _occurrence_payload(occurrence: MedicationOccurrence) -> dict:
    return {
        "id": str(occurrence.id),
        "plan_id": str(occurrence.plan_id),
        "scheduled_at": occurrence.scheduled_at.isoformat(),
        "status": occurrence.status,
        "acted_at": occurrence.acted_at.isoformat() if occurrence.acted_at else None,
    }

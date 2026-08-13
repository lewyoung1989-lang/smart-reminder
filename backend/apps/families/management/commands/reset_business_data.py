from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.families.models import Family
from apps.medication.models import MedicationPlan
from apps.medicines.models import MedicineItem
from apps.ocr.models import OCRJob
from apps.ocr.providers.storage import get_object_storage
from apps.reminders.models import ReminderRule, VoiceParseSession
from apps.workflows.models import (
    NodeRun,
    NotificationOutbox,
    TrustGrant,
    WorkflowDraft,
    WorkflowRun,
)


class Command(BaseCommand):
    help = "删除提醒、工作流、药箱和家庭数据，但保留账号。"

    def add_arguments(self, parser):
        parser.add_argument(
            "--confirm",
            action="store_true",
            help="确认执行不可恢复的业务数据重置。",
        )

    @transaction.atomic
    def handle(self, *args, **options):
        if not options["confirm"]:
            raise CommandError("必须传入 --confirm 才会执行重置。")
        storage = get_object_storage()
        photo_keys = list(
            MedicineItem.objects.exclude(photo_object_key="").values_list(
                "photo_object_key", flat=True
            )
        )
        ocr_keys = [
            key
            for image_keys in OCRJob.objects.values_list("image_keys", flat=True)
            for key in image_keys.values()
        ]
        # 从上层业务对象开始删除，交由级联关系清理运行记录和提醒实例。
        NotificationOutbox.objects.all().delete()
        NodeRun.objects.all().delete()
        WorkflowRun.objects.all().delete()
        MedicationPlan.objects.all().delete()
        ReminderRule.objects.all().delete()
        WorkflowDraft.objects.all().delete()
        TrustGrant.objects.all().delete()
        VoiceParseSession.objects.all().delete()
        OCRJob.objects.all().delete()
        MedicineItem.objects.all().delete()
        Family.objects.all().delete()
        transaction.on_commit(
            lambda: self._delete_objects(storage, {*photo_keys, *ocr_keys})
        )
        self.stdout.write(self.style.SUCCESS("业务数据已重置，账号数据已保留。"))

    def _delete_objects(self, storage, keys):
        for key in keys:
            try:
                storage.delete(key)
            except Exception:
                self.stderr.write(f"警告：对象存储清理失败，请人工删除 {key}")

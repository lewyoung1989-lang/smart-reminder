from datetime import datetime
from zoneinfo import ZoneInfo

from django.db import migrations, models


def backfill_scheduled_at(apps, schema_editor):
    ReminderRule = apps.get_model("reminders", "ReminderRule")
    rules = list(ReminderRule.objects.all())
    for rule in rules:
        try:
            value = datetime.fromisoformat(rule.schedule_json["local_datetime"])
            if value.tzinfo is None:
                value = value.replace(tzinfo=ZoneInfo(rule.timezone))
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError(
                f"Cannot migrate schedule for reminder rule {rule.id}"
            ) from exc
        rule.scheduled_at = value
    ReminderRule.objects.bulk_update(rules, ["scheduled_at"])


class Migration(migrations.Migration):
    dependencies = [
        ("reminders", "0003_voiceparsesession_parser_source"),
    ]

    operations = [
        migrations.AddField(
            model_name="reminderrule",
            name="scheduled_at",
            field=models.DateTimeField(null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="cancelled_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.RunPython(
            backfill_scheduled_at,
            reverse_code=migrations.RunPython.noop,
        ),
        migrations.AlterField(
            model_name="reminderrule",
            name="scheduled_at",
            field=models.DateTimeField(db_index=True),
        ),
    ]

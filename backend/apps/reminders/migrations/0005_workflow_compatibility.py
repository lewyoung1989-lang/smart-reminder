from django.db import migrations, models


def backfill_workflow_compatibility(apps, schema_editor):
    ReminderRule = apps.get_model("reminders", "ReminderRule")
    rules = list(ReminderRule.objects.all())
    for rule in rules:
        rule.template_key = "legacy_once"
        rule.template_version = "1.0.0"
        rule.schema_version = 1
        rule.workflow_spec_json = {
            "schema_version": 1,
            "template_key": "legacy_once",
            "template_version": "1.0.0",
            "timezone": rule.timezone,
            "nodes": [],
            "edges": [],
        }
    ReminderRule.objects.bulk_update(
        rules,
        [
            "template_key",
            "template_version",
            "schema_version",
            "workflow_spec_json",
        ],
    )


class Migration(migrations.Migration):
    dependencies = [
        ("reminders", "0004_reminderrule_lifecycle"),
    ]

    operations = [
        migrations.AddField(
            model_name="reminderrule",
            name="template_key",
            field=models.CharField(blank=True, max_length=128, null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="template_version",
            field=models.CharField(blank=True, max_length=32, null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="schema_version",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="workflow_spec_json",
            field=models.JSONField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="next_run_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="last_run_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="revision",
            field=models.PositiveIntegerField(blank=True, default=1, null=True),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="paused_reason",
            field=models.CharField(blank=True, max_length=128, null=True),
        ),
        # The legacy data backfill is intentionally irreversible.
        migrations.RunPython(backfill_workflow_compatibility),
    ]

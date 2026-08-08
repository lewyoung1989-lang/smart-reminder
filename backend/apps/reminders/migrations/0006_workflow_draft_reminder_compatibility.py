import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("reminders", "0005_workflow_compatibility"),
        ("workflows", "0002_trustgrant_expires_at"),
    ]

    operations = [
        migrations.AlterField(
            model_name="reminderrule",
            name="scheduled_at",
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AlterField(
            model_name="reminderrule",
            name="source_draft",
            field=models.OneToOneField(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="confirmed_rule",
                to="reminders.reminderdraft",
            ),
        ),
        migrations.AddField(
            model_name="reminderrule",
            name="workflow_draft",
            field=models.OneToOneField(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="confirmed_rule",
                to="workflows.workflowdraft",
            ),
        ),
    ]

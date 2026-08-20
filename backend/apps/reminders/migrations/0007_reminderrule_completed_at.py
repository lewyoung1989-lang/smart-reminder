from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("reminders", "0006_workflow_draft_reminder_compatibility"),
    ]

    operations = [
        migrations.AddField(
            model_name="reminderrule",
            name="completed_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]

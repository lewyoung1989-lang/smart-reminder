import django.db.models.deletion
import django.db.models.functions.text
import django.db.models.lookups
import django.core.validators
import uuid

from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("reminders", "0004_reminderrule_lifecycle"),
    ]

    operations = [
        migrations.CreateModel(
            name="WorkflowDraft",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("task_spec_json", models.JSONField()),
                ("workflow_spec_json", models.JSONField()),
                ("policy_json", models.JSONField()),
                ("status", models.CharField(choices=[("pending_confirmation", "Pending confirmation"), ("confirmed", "Confirmed"), ("expired", "Expired")], default="pending_confirmation", max_length=32)),
                ("expires_at", models.DateTimeField()),
                ("confirmed_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name="WorkflowTemplate",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("template_key", models.CharField(max_length=128)),
                ("version", models.CharField(max_length=32)),
                ("status", models.CharField(choices=[("active", "Active"), ("deprecated", "Deprecated"), ("retired", "Retired")], default="active", max_length=32)),
                ("capabilities_json", models.JSONField(default=list)),
            ],
            options={
                "constraints": [models.UniqueConstraint(fields=("template_key", "version"), name="workflow_template_key_version_unique")],
            },
        ),
        migrations.CreateModel(
            name="TrustGrant",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("capability_signature", models.CharField(max_length=64, validators=[django.core.validators.RegexValidator(message="Enter a 64-character lowercase SHA-256 hexadecimal value.", regex="^[0-9a-f]{64}$")])),
                ("template_key", models.CharField(max_length=128)),
                ("template_major_version", models.PositiveIntegerField()),
                ("scope_json", models.JSONField(default=dict)),
                ("status", models.CharField(choices=[("active", "Active"), ("revoked", "Revoked")], default="active", max_length=32)),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
            options={
                "constraints": [models.UniqueConstraint(condition=models.Q(("status", "active")), fields=("user", "capability_signature", "template_key", "template_major_version"), name="workflow_active_grant_unique"), models.CheckConstraint(condition=models.Q(("capability_signature__regex", "^[0-9a-f]{64}$"), django.db.models.lookups.Exact(django.db.models.functions.text.Length("capability_signature"), 64)), name="workflow_grant_signature_sha256_valid")],
            },
        ),
        migrations.CreateModel(
            name="WorkflowRun",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("idempotency_key", models.CharField(max_length=128)),
                ("status", models.CharField(choices=[("pending", "Pending"), ("running", "Running"), ("succeeded", "Succeeded"), ("failed", "Failed"), ("cancelled", "Cancelled")], default="pending", max_length=32)),
                ("scheduled_for", models.DateTimeField(blank=True, null=True)),
                ("started_at", models.DateTimeField(blank=True, null=True)),
                ("finished_at", models.DateTimeField(blank=True, null=True)),
                ("result_json", models.JSONField(default=dict)),
                ("workflow", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="workflow_runs", to="reminders.reminderrule")),
            ],
            options={
                "constraints": [models.UniqueConstraint(fields=("workflow", "idempotency_key"), name="workflow_run_idempotency_unique")],
            },
        ),
    ]

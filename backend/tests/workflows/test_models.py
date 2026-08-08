from contextlib import contextmanager
from datetime import datetime, timedelta
import importlib
from zoneinfo import ZoneInfo

import pytest
from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import IntegrityError, connection, connections, models, transaction
from django.db.migrations.exceptions import IrreversibleError
from django.db.migrations.executor import MigrationExecutor
from django.db.migrations.recorder import MigrationRecorder
from django.db.utils import ConnectionHandler
from django.utils import timezone

from apps.reminders.models import ReminderDraft, ReminderRule, VoiceParseSession
from apps.workflows.models import (
    TrustGrant,
    WorkflowDraft,
    WorkflowRun,
    WorkflowTemplate,
)


def create_reminder_rule(user, *, suffix=""):
    session = VoiceParseSession.objects.create(
        user=user,
        transcript_sha256=("d" * 63) + (suffix or "0"),
        expires_at=timezone.now() + timedelta(hours=1),
    )
    draft = ReminderDraft.objects.create(
        session=session,
        draft_json={},
        expires_at=timezone.now() + timedelta(hours=1),
    )
    return ReminderRule.objects.create(
        owner=user,
        title=f"workflow rule {suffix}",
        timezone="UTC",
        schedule_json={"type": "once"},
        conditions_json={},
        severity="notification",
        scheduled_at=timezone.now(),
        source_draft=draft,
    )


@contextmanager
def isolated_default_connection(tmp_path, database_name):
    isolated_connection = ConnectionHandler(
        {
            "default": {
                "ENGINE": "django.db.backends.sqlite3",
                "NAME": str(tmp_path / database_name),
            },
        }
    )["default"]
    default_connection = connections["default"]
    connections._connections.default = isolated_connection
    try:
        yield isolated_connection
    finally:
        isolated_connection.close()
        connections._connections.default = default_connection


@pytest.mark.django_db
def test_trust_grants_are_isolated_by_user(django_user_model):
    first_user = django_user_model.objects.create_user(
        username="workflow-first",
        password="test-password",
    )
    second_user = django_user_model.objects.create_user(
        username="workflow-second",
        password="test-password",
    )
    signature = "a" * 64

    first_grant = TrustGrant.objects.create(
        user=first_user,
        capability_signature=signature,
        template_key="medication_once",
        template_major_version=1,
        scope_json={"reminder_ids": []},
    )
    second_grant = TrustGrant.objects.create(
        user=second_user,
        capability_signature=signature,
        template_key="medication_once",
        template_major_version=1,
        scope_json={"reminder_ids": []},
    )

    assert first_grant.user_id != second_grant.user_id
    assert TrustGrant.objects.filter(capability_signature=signature).count() == 2


@pytest.mark.django_db
def test_active_trust_grant_is_unique_until_revoked(user):
    grant = TrustGrant.objects.create(
        user=user,
        capability_signature="b" * 64,
        template_key="medication_once",
        template_major_version=1,
        scope_json={"reminder_ids": []},
    )

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            TrustGrant.objects.create(
                user=user,
                capability_signature="b" * 64,
                template_key="medication_once",
                template_major_version=1,
                scope_json={},
            )

    grant.status = TrustGrant.Status.REVOKED
    grant.revoked_at = timezone.now()
    grant.save(update_fields=["status", "revoked_at"])

    replacement = TrustGrant.objects.create(
        user=user,
        capability_signature="b" * 64,
        template_key="medication_once",
        template_major_version=1,
        scope_json={},
    )
    assert replacement.status == TrustGrant.Status.ACTIVE


@pytest.mark.django_db
def test_trust_grant_full_clean_rejects_non_sha256_signature(user):
    grant = TrustGrant(
        user=user,
        capability_signature="not-a-sha256",
        template_key="medication_once",
        template_major_version=1,
        scope_json={"reminder_ids": []},
    )

    with pytest.raises(ValidationError, match="SHA-256"):
        grant.full_clean()


@pytest.mark.django_db
@pytest.mark.parametrize(
    "capability_signature",
    ["A" * 64, ("a" * 64) + "\n", "a" * 65],
)
def test_trust_grant_database_rejects_non_sha256_signature(
    user,
    capability_signature,
):
    with transaction.atomic():
        with pytest.raises(IntegrityError):
            TrustGrant.objects.create(
                user=user,
                capability_signature=capability_signature,
                template_key="medication_once",
                template_major_version=1,
                scope_json={},
            )


def test_signature_constraint_does_not_register_a_global_length_lookup():
    assert "length" not in models.CharField.get_lookups()


@pytest.mark.django_db
def test_workflow_template_can_be_created():
    template = WorkflowTemplate.objects.create(
        template_key="medication_once",
        version="1.0.0",
        capabilities_json=["schedule.reminder"],
    )

    assert template.status == WorkflowTemplate.Status.ACTIVE
    assert template.capabilities_json == ["schedule.reminder"]


@pytest.mark.django_db
def test_workflow_run_idempotency_key_is_unique_per_reminder_rule(user):
    rule = create_reminder_rule(user)
    WorkflowRun.objects.create(
        workflow=rule,
        idempotency_key="run-001",
        result_json={},
    )

    with transaction.atomic():
        with pytest.raises(IntegrityError):
            WorkflowRun.objects.create(
                workflow=rule,
                idempotency_key="run-001",
                result_json={},
            )


@pytest.mark.django_db
def test_workflow_draft_requires_explicit_expiry_from_service_caller(user):
    with transaction.atomic():
        with pytest.raises(IntegrityError):
            WorkflowDraft.objects.create(
                user=user,
                task_spec_json={},
                workflow_spec_json={},
                policy_json={},
            )

    expires_at = timezone.now() + timedelta(minutes=30)
    draft = WorkflowDraft.objects.create(
        user=user,
        task_spec_json={},
        workflow_spec_json={},
        policy_json={},
        expires_at=expires_at,
    )
    assert draft.expires_at == expires_at


def assert_workflow_compatibility_migration_preserves_legacy_reminder_data(
    connection,
):
    executor = MigrationExecutor(connection)
    executor.migrate([("reminders", "0004_reminderrule_lifecycle")])
    old_apps = executor.loader.project_state(
        [("reminders", "0004_reminderrule_lifecycle")]
    ).apps
    app_label, model_name = settings.AUTH_USER_MODEL.split(".")
    User = old_apps.get_model(app_label, model_name)
    Session = old_apps.get_model("reminders", "VoiceParseSession")
    Draft = old_apps.get_model("reminders", "ReminderDraft")
    Rule = old_apps.get_model("reminders", "ReminderRule")

    user = User.objects.create(username="workflow-migration-owner")
    session = Session.objects.create(
        user=user,
        transcript_sha256="c" * 64,
        expires_at="2026-08-08T00:00:00+00:00",
    )
    draft = Draft.objects.create(
        session=session,
        draft_json={},
        expires_at="2026-08-08T00:00:00+00:00",
    )
    scheduled_at = datetime(2026, 8, 7, 8, 30, tzinfo=ZoneInfo("Asia/Shanghai"))
    schedule_json = {
        "type": "once",
        "local_datetime": "2026-08-07T08:30:00+08:00",
        "timezone": "Asia/Shanghai",
    }
    conditions_json = {"weather": "clear"}
    rule = Rule.objects.create(
        owner=user,
        title="legacy reminder",
        timezone="Asia/Shanghai",
        schedule_json=schedule_json,
        conditions_json=conditions_json,
        severity="notification",
        scheduled_at=scheduled_at,
        source_draft=draft,
    )

    executor = MigrationExecutor(connection)
    executor.migrate([("reminders", "0005_workflow_compatibility")])
    migrated_apps = executor.loader.project_state(
        [("reminders", "0005_workflow_compatibility")]
    ).apps
    MigratedRule = migrated_apps.get_model("reminders", "ReminderRule")
    migrated_rule = MigratedRule.objects.get(id=rule.id)

    assert migrated_rule.schedule_json == schedule_json
    assert migrated_rule.conditions_json == conditions_json
    assert migrated_rule.scheduled_at == scheduled_at
    assert migrated_rule.template_key == "legacy_once"
    assert migrated_rule.template_version == "1.0.0"
    assert migrated_rule.schema_version == 1
    assert migrated_rule.next_run_at is None
    assert migrated_rule.last_run_at is None
    assert migrated_rule.revision == 1
    assert migrated_rule.paused_reason is None
    assert migrated_rule.workflow_spec_json == {
        "schema_version": 1,
        "template_key": "legacy_once",
        "template_version": "1.0.0",
        "timezone": "Asia/Shanghai",
        "nodes": [],
        "edges": [],
    }


@pytest.mark.django_db(transaction=True)
def test_workflow_compatibility_migration_preserves_legacy_reminder_data(tmp_path):
    with isolated_default_connection(
        tmp_path,
        "workflow-compatibility.sqlite3",
    ) as isolated_connection:
        assert_workflow_compatibility_migration_preserves_legacy_reminder_data(
            isolated_connection,
        )


@pytest.mark.django_db(transaction=True)
def test_workflow_compatibility_migration_is_irreversible_and_preserves_workflows(
    tmp_path,
):
    with isolated_default_connection(
        tmp_path,
        "workflow-irreversible.sqlite3",
    ) as isolated_connection:
        assert_workflow_compatibility_migration_is_irreversible_and_preserves_workflows(
            isolated_connection,
        )


def assert_workflow_compatibility_migration_is_irreversible_and_preserves_workflows(
    connection,
):
    executor = MigrationExecutor(connection)
    executor.migrate(
        [
            ("reminders", "0005_workflow_compatibility"),
            ("workflows", "0001_initial"),
        ]
    )
    apps = executor.loader.project_state(
        [
            ("reminders", "0005_workflow_compatibility"),
            ("workflows", "0001_initial"),
        ]
    ).apps
    app_label, model_name = settings.AUTH_USER_MODEL.split(".")
    User = apps.get_model(app_label, model_name)
    Session = apps.get_model("reminders", "VoiceParseSession")
    Draft = apps.get_model("reminders", "ReminderDraft")
    Rule = apps.get_model("reminders", "ReminderRule")
    Template = apps.get_model("workflows", "WorkflowTemplate")
    WorkflowDraftModel = apps.get_model("workflows", "WorkflowDraft")
    Run = apps.get_model("workflows", "WorkflowRun")

    user = User.objects.create(username="post-migration-owner")
    session = Session.objects.create(
        user=user,
        transcript_sha256="e" * 64,
        expires_at="2026-08-08T00:00:00+00:00",
    )
    draft = Draft.objects.create(
        session=session,
        draft_json={},
        expires_at="2026-08-08T00:00:00+00:00",
    )
    legacy_spec = {
        "schema_version": 1,
        "template_key": "legacy_once",
        "template_version": "1.0.0",
        "timezone": "Asia/Shanghai",
        "nodes": [],
        "edges": [],
    }
    rule = Rule.objects.create(
        owner=user,
        title="post-migration reminder",
        timezone="Asia/Shanghai",
        schedule_json={"type": "once"},
        conditions_json={},
        severity="notification",
        scheduled_at="2026-08-07T00:30:00+00:00",
        source_draft=draft,
        template_key="legacy_once",
        template_version="1.0.0",
        schema_version=1,
        workflow_spec_json=legacy_spec,
    )
    template = Template.objects.create(
        template_key="medication_once",
        version="1.0.0",
        capabilities_json=["schedule.reminder"],
    )
    workflow_draft = WorkflowDraftModel.objects.create(
        user=user,
        task_spec_json={},
        workflow_spec_json={},
        policy_json={},
        expires_at="2026-08-08T00:00:00+00:00",
    )
    run = Run.objects.create(
        workflow=rule,
        idempotency_key="irreversible-run",
        result_json={},
    )
    recorder = MigrationRecorder(connection)
    migrations_before = recorder.applied_migrations()

    # The code can roll back, but the legacy data migration must not downgrade.
    executor = MigrationExecutor(connection)
    with pytest.raises(IrreversibleError):
        executor.migrate([("reminders", "0004_reminderrule_lifecycle")])

    current_apps = MigrationExecutor(connection).loader.project_state(
        [
            ("reminders", "0005_workflow_compatibility"),
            ("workflows", "0001_initial"),
        ]
    ).apps
    CurrentRule = current_apps.get_model("reminders", "ReminderRule")
    CurrentTemplate = current_apps.get_model("workflows", "WorkflowTemplate")
    CurrentWorkflowDraft = current_apps.get_model("workflows", "WorkflowDraft")
    CurrentRun = current_apps.get_model("workflows", "WorkflowRun")
    preserved_rule = CurrentRule.objects.get(id=rule.id)
    assert preserved_rule.template_key == "legacy_once"
    assert preserved_rule.template_version == "1.0.0"
    assert preserved_rule.schema_version == 1
    assert preserved_rule.workflow_spec_json == legacy_spec
    assert CurrentTemplate.objects.get(id=template.id).template_key == "medication_once"
    assert CurrentWorkflowDraft.objects.get(id=workflow_draft.id).user_id == user.id
    assert CurrentRun.objects.get(id=run.id).workflow_id == rule.id
    assert MigrationRecorder(connection).applied_migrations() == migrations_before


@pytest.mark.django_db(transaction=True)
def test_workflow_run_empty_idempotency_key_blocks_0004_upgrade(tmp_path):
    with isolated_default_connection(
        tmp_path,
        "workflow-run-idempotency-preflight.sqlite3",
    ) as isolated_connection:
        executor = MigrationExecutor(isolated_connection)
        executor.migrate([("workflows", "0003_noderun_notificationoutbox")])
        apps = executor.loader.project_state(
            [("workflows", "0003_noderun_notificationoutbox")]
        ).apps
        app_label, model_name = settings.AUTH_USER_MODEL.split(".")
        User = apps.get_model(app_label, model_name)
        Session = apps.get_model("reminders", "VoiceParseSession")
        Draft = apps.get_model("reminders", "ReminderDraft")
        Rule = apps.get_model("reminders", "ReminderRule")
        Run = apps.get_model("workflows", "WorkflowRun")

        user = User.objects.create(username="empty-run-idempotency-owner")
        session = Session.objects.create(
            user=user,
            transcript_sha256="f" * 64,
            expires_at="2026-08-08T00:00:00+00:00",
        )
        draft = Draft.objects.create(
            session=session,
            draft_json={},
            expires_at="2026-08-08T00:00:00+00:00",
        )
        rule = Rule.objects.create(
            owner=user,
            title="empty run idempotency",
            timezone="UTC",
            schedule_json={"type": "once"},
            conditions_json={},
            severity="notification",
            scheduled_at="2026-08-08T00:00:00+00:00",
            source_draft=draft,
        )
        Run.objects.create(workflow=rule, idempotency_key="", result_json={})

        executor = MigrationExecutor(isolated_connection)
        with pytest.raises(RuntimeError, match="empty idempotency_key"):
            executor.migrate([("workflows", "0004_workflowrun_idempotency_key_nonempty")])


def test_workflow_run_idempotency_preflight_uses_migration_connection_alias():
    migration = importlib.import_module(
        "apps.workflows.migrations.0004_workflowrun_idempotency_key_nonempty"
    )

    class FakeQuerySet:
        def filter(self, **kwargs):
            self.filters = kwargs
            return self

        def exists(self):
            return False

    class FakeManager:
        def __init__(self):
            self.queryset = FakeQuerySet()
            self.alias = None

        def using(self, alias):
            self.alias = alias
            return self.queryset

    class FakeWorkflowRun:
        objects = FakeManager()

    class FakeApps:
        def get_model(self, app_label, model_name):
            assert (app_label, model_name) == ("workflows", "WorkflowRun")
            return FakeWorkflowRun

    class FakeConnection:
        alias = "migration-test"

    class FakeSchemaEditor:
        connection = FakeConnection()

    migration.reject_empty_workflow_run_idempotency_keys(
        FakeApps(),
        FakeSchemaEditor(),
    )

    assert FakeWorkflowRun.objects.alias == "migration-test"
    assert FakeWorkflowRun.objects.queryset.filters == {"idempotency_key": ""}

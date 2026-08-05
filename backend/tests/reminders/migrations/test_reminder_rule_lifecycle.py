from pathlib import Path

import pytest
from django.conf import settings
from django.db import connection
from django.db.migrations.executor import MigrationExecutor


MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "apps/reminders/migrations/0004_reminderrule_lifecycle.py"
)


@pytest.mark.django_db(transaction=True)
def test_lifecycle_migration_backfills_aware_and_naive_schedule_times():
    assert MIGRATION.exists(), "lifecycle migration must exist"

    executor = MigrationExecutor(connection)
    executor.migrate([("reminders", "0003_voiceparsesession_parser_source")])
    old_apps = executor.loader.project_state(
        [("reminders", "0003_voiceparsesession_parser_source")]
    ).apps
    app_label, model_name = settings.AUTH_USER_MODEL.split(".")
    User = old_apps.get_model(app_label, model_name)
    Session = old_apps.get_model("reminders", "VoiceParseSession")
    Draft = old_apps.get_model("reminders", "ReminderDraft")
    Rule = old_apps.get_model("reminders", "ReminderRule")

    user = User.objects.create(username="migration-owner")
    schedules = [
        "2026-08-04T07:30:00+08:00",
        "2026-08-04T07:30:00",
    ]
    rule_ids = []
    for index, local_datetime in enumerate(schedules):
        session = Session.objects.create(
            user=user,
            transcript_sha256=str(index) * 64,
            expires_at="2026-08-05T00:00:00+00:00",
        )
        draft = Draft.objects.create(
            session=session,
            draft_json={},
            expires_at="2026-08-05T00:00:00+00:00",
        )
        rule = Rule.objects.create(
            owner=user,
            title=f"提醒 {index}",
            timezone="Asia/Shanghai",
            schedule_json={
                "type": "once",
                "local_datetime": local_datetime,
                "timezone": "Asia/Shanghai",
            },
            severity="notification",
            source_draft=draft,
        )
        rule_ids.append(rule.id)

    executor = MigrationExecutor(connection)
    executor.migrate([("reminders", "0004_reminderrule_lifecycle")])
    new_apps = executor.loader.project_state(
        [("reminders", "0004_reminderrule_lifecycle")]
    ).apps
    MigratedRule = new_apps.get_model("reminders", "ReminderRule")

    values = [
        MigratedRule.objects.get(id=rule_id).scheduled_at.isoformat()
        for rule_id in rule_ids
    ]
    assert values == [
        "2026-08-03T23:30:00+00:00",
        "2026-08-03T23:30:00+00:00",
    ]

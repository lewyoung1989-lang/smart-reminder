"""快速创建入口的工作流意图路由测试。"""

from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from apps.reminders.models import ReminderDraft
from apps.reminders.domain.natural_language import NaturalLanguageDraft
from apps.reminders.domain.schemas import ReminderDraftData, Schedule
from apps.workflows.domain.schemas import TaskSpec
from apps.workflows.models import WorkflowDraft


CREATE_URL = "/api/v1/reminder-drafts"


@pytest.mark.django_db
def test_daily_medication_text_routes_to_workflow_draft(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "我每天早上9点钟要吃一次药"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "workflow"
    assert payload["task"]["template_hint"] == "medication_cycle"
    assert payload["policy"]["decision"] == "needs_clarification"
    assert payload["policy"]["question"] == "请补充药品剂量和服药周期"
    assert WorkflowDraft.objects.count() == 1
    assert ReminderDraft.objects.count() == 0


@pytest.mark.django_db
def test_daily_branded_medicine_without_yao_routes_to_workflow_draft(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "我每天晚上10点吃布洛芬"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "workflow"
    assert payload["task"]["template_hint"] == "medication_cycle"
    assert payload["task"]["slots"]["medicine_name"] == "布洛芬"
    assert payload["task"]["slots"]["frequency"] == "daily"
    assert payload["task"]["slots"]["time_of_day"] == "22:00"
    assert payload["policy"]["decision"] == "needs_clarification"
    assert WorkflowDraft.objects.count() == 1
    assert ReminderDraft.objects.count() == 0


@pytest.mark.django_db
def test_one_time_reminder_stays_on_reminder_flow(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "1分钟后提醒我喝水"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "reminder"
    assert payload["parser_source"] == "local"
    assert WorkflowDraft.objects.count() == 0
    assert ReminderDraft.objects.count() == 1


@pytest.mark.django_db
def test_model_one_time_reminder_stays_on_reminder_flow(
    api_client, user, settings, mocker
):
    settings.DEEPSEEK_API_KEY = "test-key"
    mocker.patch(
        "apps.reminders.api.views.DeepSeekNaturalLanguageProvider.parse",
        return_value=NaturalLanguageDraft(
            draft_type="reminder",
            reminder=ReminderDraftData(
                title="喝水",
                schedule=Schedule(
                    local_datetime=datetime(
                        2026, 8, 21, 9, 0, tzinfo=ZoneInfo("Asia/Shanghai")
                    ),
                    timezone="Asia/Shanghai",
                ),
                precheck=None,
                severity="notification",
            ),
        ),
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "明天早上9点提醒我喝水"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "reminder"
    assert payload["parser_source"] == "deepseek"
    assert WorkflowDraft.objects.count() == 0
    assert ReminderDraft.objects.count() == 1


@pytest.mark.django_db
def test_quick_create_uses_model_workflow_task_before_rule_routing(
    api_client, user, settings, mocker
):
    settings.DEEPSEEK_API_KEY = "test-key"
    mocker.patch(
        "apps.reminders.api.views.DeepSeekNaturalLanguageProvider.parse",
        return_value=NaturalLanguageDraft(
            draft_type="workflow",
            workflow=TaskSpec(
                template_hint="medication_cycle",
                title="用药提醒",
                slots={
                    "medicine_name": "测试药品A",
                    "dose_text": "1片",
                    "frequency": "daily",
                    "time_of_day": "20:00",
                },
                requested_capabilities=[
                    "medicine.schedule",
                    "notification.important",
                ],
            ),
        ),
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "以后晚上使用测试药品A"},
        format="json",
    )

    assert response.status_code == 201
    assert response.json()["draft_type"] == "workflow"
    assert response.json()["workflow"]["template_key"] == "medication_cycle"


@pytest.mark.django_db
def test_deterministic_workflow_overrides_model_one_time_medication_misroute(
    api_client, user, settings, mocker
):
    settings.DEEPSEEK_API_KEY = "test-key"
    mocker.patch(
        "apps.reminders.api.views.DeepSeekNaturalLanguageProvider.parse",
        return_value=NaturalLanguageDraft(
            draft_type="reminder",
            reminder=ReminderDraftData(
                title="吃依巴斯汀",
                schedule=Schedule(
                    local_datetime=datetime(
                        2026, 8, 21, 8, 0, tzinfo=ZoneInfo("Asia/Shanghai")
                    ),
                    timezone="Asia/Shanghai",
                ),
                precheck=None,
                severity="notification",
                ambiguities=["系统仅支持一次性提醒"],
            ),
        ),
    )
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "每天我都要吃依巴斯汀，早上8点，晚上八点，一次一片"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "workflow"
    assert payload["task"]["template_hint"] == "medication_cycle"
    assert payload["task"]["slots"] == {
        "medicine_name": "依巴斯汀",
        "dose_text": "一片",
        "frequency": "daily",
        "time_of_day": "08:00",
        "times": ["08:00", "20:00"],
    }
    assert payload["workflow"]["template_key"] == "medication_cycle"
    assert WorkflowDraft.objects.count() == 1
    assert ReminderDraft.objects.count() == 0


@pytest.mark.django_db
def test_eating_text_without_medicine_is_not_hijacked(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "明天9点提醒我吃火锅"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "reminder"
    assert WorkflowDraft.objects.count() == 0


@pytest.mark.django_db
def test_daily_eating_text_without_medicine_is_not_hijacked(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "我每天晚上10点吃火锅"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "reminder"
    assert WorkflowDraft.objects.count() == 0


@pytest.mark.django_db
def test_incomplete_departure_falls_back_to_reminder_flow(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "我晚上8点要出门去地铁站"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "reminder"
    assert WorkflowDraft.objects.count() == 0


@pytest.mark.django_db
def test_complete_departure_routes_to_workflow_draft(api_client, user):
    api_client.force_authenticate(user)

    response = api_client.post(
        CREATE_URL,
        {"text": "明天八点到虹桥火车站，坐公交出门"},
        format="json",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["draft_type"] == "workflow"
    assert payload["workflow"]["template_key"] == "smart_departure"
    assert payload["policy"]["decision"] == "needs_confirmation"


@pytest.mark.django_db
def test_routed_workflow_draft_confirms_via_workflow_endpoint(api_client, user):
    api_client.force_authenticate(user)
    created = api_client.post(
        CREATE_URL,
        {"text": "明天八点到虹桥火车站，坐公交出门"},
        format="json",
    ).json()

    confirm = api_client.post(f"/api/v1/workflow-drafts/{created['id']}/confirm")

    assert confirm.status_code == 201
    assert WorkflowDraft.objects.get(id=created["id"]).status == "confirmed"


@pytest.mark.django_db
def test_routed_clarification_draft_cannot_confirm(api_client, user):
    api_client.force_authenticate(user)
    created = api_client.post(
        CREATE_URL,
        {"text": "我每天早上9点钟要吃一次药"},
        format="json",
    ).json()

    confirm = api_client.post(f"/api/v1/workflow-drafts/{created['id']}/confirm")

    assert confirm.status_code == 409
    assert confirm.json()["code"] == "workflow_needs_clarification"

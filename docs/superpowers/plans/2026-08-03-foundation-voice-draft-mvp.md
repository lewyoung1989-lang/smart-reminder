# Foundation And Voice Draft MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a runnable Django foundation and the first safe voice-reminder vertical slice: authenticated transcript submission, deterministic parsing, persisted draft review, and idempotent confirmation, plus Flutter and Docker project foundations.

**Architecture:** The repository is a monorepo with `backend/` for Django/DRF and `app/` for Flutter. Voice input produces a short-lived server-side draft; the parser is an isolated domain service and no reminder is created until the confirmation endpoint succeeds. Local tests use SQLite and an injected clock, while Docker Compose maps the same Django code to PostgreSQL, Redis, Celery, and MinIO.

**Tech Stack:** Python 3.13, Django 5.2, Django REST Framework 3.16, Pydantic 2, pytest, Flutter/Dart, PostgreSQL 16, Redis 7, Celery 5, MinIO, Docker Compose.

---

## Scope And File Map

This plan implements only the first independently testable subsystem from the full product design. Alibaba Cloud ASR, DeepSeek, AlarmKit, medicine cabinet, OCR, family sharing, and production deployment remain separate later plans.

- `backend/config/`: Django settings, URL routing, WSGI and ASGI entry points.
- `backend/apps/core/`: health endpoint and shared API behavior.
- `backend/apps/reminders/models.py`: reminder rules, transient voice sessions, and drafts.
- `backend/apps/reminders/domain/voice_parser.py`: deterministic Chinese reminder parser with no Django dependency.
- `backend/apps/reminders/api/`: request serializers, authenticated views, and routes.
- `backend/tests/`: domain, API, persistence, and confirmation tests.
- `app/lib/`: Flutter application shell, voice draft client, and confirmation screen.
- `app/test/`: Flutter widget test for the voice draft flow.
- `compose.yaml`: local PostgreSQL, Redis, MinIO, API, worker, and beat services.

## Task 1: Django Project Foundation And Health Endpoint

**Files:**
- Create: `backend/requirements/base.txt`
- Create: `backend/requirements/dev.txt`
- Create: `backend/manage.py`
- Create: `backend/config/settings.py`
- Create: `backend/config/urls.py`
- Create: `backend/config/asgi.py`
- Create: `backend/config/wsgi.py`
- Create: `backend/apps/core/views.py`
- Test: `backend/tests/core/test_health.py`
- Create: `backend/pytest.ini`

- [x] **Step 1: Create the dependency and test configuration files**

```text
# backend/requirements/base.txt
Django==5.2.5
djangorestframework==3.16.1
pydantic==2.11.7
psycopg[binary]==3.2.9
celery==5.5.3
redis==6.4.0
gunicorn==23.0.0
```

```text
# backend/requirements/dev.txt
-r base.txt
pytest==8.4.1
pytest-django==4.11.1
```

```ini
# backend/pytest.ini
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = test_*.py
addopts = -q
```

- [x] **Step 2: Install the backend development dependencies**

Run: `python3 -m venv .venv && .venv/bin/python -m pip install -r backend/requirements/dev.txt`

Expected: all pinned packages install successfully.

- [x] **Step 3: Write the failing health endpoint test**

```python
def test_health_returns_service_status(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "smart-reminder-api"}
```

- [x] **Step 4: Run the health test and verify RED**

Run: `.venv/bin/pytest backend/tests/core/test_health.py -q`

Expected: FAIL because the Django project or route does not exist.

- [x] **Step 5: Add the minimal Django configuration and health view**

```python
# backend/apps/core/views.py
from django.http import JsonResponse


def health(request):
    return JsonResponse({"status": "ok", "service": "smart-reminder-api"})
```

```python
# backend/config/urls.py
from django.urls import path
from apps.core.views import health

urlpatterns = [path("api/v1/health", health, name="health")]
```

`settings.py` must use SQLite by default, set `USE_TZ = True`, `TIME_ZONE = "UTC"`, and register Django auth, contenttypes, sessions, DRF, core, and reminders applications.

- [x] **Step 6: Run the health test and verify GREEN**

Run: `.venv/bin/pytest backend/tests/core/test_health.py -q`

Expected: `1 passed`.

- [x] **Step 7: Commit the foundation**

```bash
git add backend
git commit -m "build: add Django API foundation"
```

## Task 2: Deterministic Chinese Voice Reminder Parser

**Files:**
- Create: `backend/apps/reminders/domain/schemas.py`
- Create: `backend/apps/reminders/domain/voice_parser.py`
- Test: `backend/tests/reminders/domain/test_voice_parser.py`

- [x] **Step 1: Write failing tests for the agreed voice example and ambiguity behavior**

```python
from datetime import datetime
from zoneinfo import ZoneInfo

from apps.reminders.domain.voice_parser import parse_voice_reminder


NOW = datetime(2026, 8, 3, 10, 0, tzinfo=ZoneInfo("Asia/Shanghai"))


def test_parses_tomorrow_alarm_with_weather_condition():
    result = parse_voice_reminder(
        "明天早上七点半叫我起床，先查未来两小时天气，如果下雨提醒我带伞。",
        now=NOW,
        timezone="Asia/Shanghai",
    )
    assert result.intent == "create_reminder"
    assert result.schedule.local_datetime.isoformat() == "2026-08-04T07:30:00+08:00"
    assert result.precheck.condition.window_minutes == 120
    assert result.precheck.condition.value == 40
    assert result.severity == "alarm"
    assert result.ambiguities == []


def test_missing_time_returns_ambiguity_instead_of_guessing():
    result = parse_voice_reminder("下雨提醒我带伞", now=NOW, timezone="Asia/Shanghai")
    assert result.schedule is None
    assert result.ambiguities == ["缺少提醒时间"]
```

- [x] **Step 2: Run parser tests and verify RED**

Run: `.venv/bin/pytest backend/tests/reminders/domain/test_voice_parser.py -q`

Expected: FAIL with `ModuleNotFoundError` for `voice_parser`.

- [x] **Step 3: Implement strict Pydantic schemas and the minimal parser**

```python
def parse_voice_reminder(transcript: str, *, now: datetime, timezone: str) -> ReminderDraftData:
    local_now = now.astimezone(ZoneInfo(timezone))
    scheduled_at = _parse_day_and_time(transcript, local_now)
    weather = _weather_precheck(transcript)
    ambiguities = [] if scheduled_at else ["缺少提醒时间"]
    return ReminderDraftData(
        intent="create_reminder",
        title="起床并查看天气" if "起床" in transcript else "语音提醒",
        schedule=Schedule(local_datetime=scheduled_at, timezone=timezone) if scheduled_at else None,
        precheck=weather,
        severity="alarm" if "起床" in transcript or "闹钟" in transcript else "notification",
        condition_met_message="未来两小时可能有雨，建议带伞" if weather else None,
        ambiguities=ambiguities,
    )
```

The parser must only recognize the v1 whitelist: tomorrow/today, Chinese hour numbers 0-23, `半`, explicit minute values, two-hour rain precheck, umbrella advice, and alarm severity. Unsupported content remains in the transcript but does not become executable fields.

- [x] **Step 4: Run parser tests and verify GREEN**

Run: `.venv/bin/pytest backend/tests/reminders/domain/test_voice_parser.py -q`

Expected: `2 passed`.

- [x] **Step 5: Commit the parser**

```bash
git add backend/apps/reminders/domain backend/tests/reminders/domain
git commit -m "feat: parse deterministic voice reminders"
```

## Task 3: Persist Authenticated Voice Drafts

**Files:**
- Create: `backend/apps/reminders/models.py`
- Create: `backend/apps/reminders/api/serializers.py`
- Create: `backend/apps/reminders/api/views.py`
- Create: `backend/apps/reminders/api/urls.py`
- Modify: `backend/config/urls.py`
- Test: `backend/tests/reminders/api/test_voice_drafts.py`

- [x] **Step 1: Write a failing authenticated API test**

```python
import pytest


@pytest.mark.django_db
def test_authenticated_user_creates_reviewable_voice_draft(api_client, user):
    api_client.force_authenticate(user)
    response = api_client.post(
        "/api/v1/voice/reminder-drafts",
        {"transcript": "明天早上七点半叫我起床，先查未来两小时天气，如果下雨提醒我带伞。"},
        format="json",
    )
    assert response.status_code == 201
    assert response.json()["status"] == "pending_confirmation"
    assert response.json()["draft"]["severity"] == "alarm"
    assert response.json()["draft"]["ambiguities"] == []
```

- [x] **Step 2: Run the API test and verify RED**

Run: `.venv/bin/pytest backend/tests/reminders/api/test_voice_drafts.py -q`

Expected: FAIL because the model and endpoint do not exist.

- [x] **Step 3: Add transient session and draft models**

```python
class VoiceParseSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    transcript_sha256 = models.CharField(max_length=64)
    status = models.CharField(max_length=32, default="parsed")
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)


class ReminderDraft(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.OneToOneField(VoiceParseSession, on_delete=models.CASCADE)
    draft_json = models.JSONField()
    ambiguities_json = models.JSONField(default=list)
    status = models.CharField(max_length=32, default="pending_confirmation")
    expires_at = models.DateTimeField()
    confirmed_at = models.DateTimeField(null=True)
```

The raw transcript must not be persisted. Store only its SHA-256 digest and the structured draft.

- [x] **Step 4: Implement serializer and authenticated POST view**

The serializer accepts only a non-empty `transcript` with a 500-character maximum. The view calls `parse_voice_reminder`, stores the session and draft in one transaction, uses the authenticated user's timezone with `Asia/Shanghai` as the current v1 default, and returns `201`.

- [x] **Step 5: Create and apply migrations**

Run: `.venv/bin/python backend/manage.py makemigrations reminders && .venv/bin/python backend/manage.py migrate`

Expected: reminder migrations are created and all migrations apply.

- [x] **Step 6: Run API tests and verify GREEN**

Run: `.venv/bin/pytest backend/tests/reminders/api/test_voice_drafts.py -q`

Expected: authenticated creation passes; add and pass a second test asserting anonymous requests return `403`.

- [x] **Step 7: Commit draft persistence and API**

```bash
git add backend
git commit -m "feat: create authenticated voice reminder drafts"
```

## Task 4: Idempotent Draft Confirmation

**Files:**
- Modify: `backend/apps/reminders/models.py`
- Modify: `backend/apps/reminders/api/views.py`
- Modify: `backend/apps/reminders/api/urls.py`
- Test: `backend/tests/reminders/api/test_voice_confirmation.py`

- [x] **Step 1: Write failing confirmation tests**

```python
@pytest.mark.django_db
def test_confirmation_creates_one_reminder_rule(api_client, user, valid_draft):
    api_client.force_authenticate(user)
    first = api_client.post(f"/api/v1/voice/reminder-drafts/{valid_draft.id}/confirm")
    second = api_client.post(f"/api/v1/voice/reminder-drafts/{valid_draft.id}/confirm")
    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json()["reminder_id"] == second.json()["reminder_id"]
    assert ReminderRule.objects.filter(owner=user).count() == 1


@pytest.mark.django_db
def test_ambiguous_draft_cannot_be_confirmed(api_client, user, ambiguous_draft):
    api_client.force_authenticate(user)
    response = api_client.post(f"/api/v1/voice/reminder-drafts/{ambiguous_draft.id}/confirm")
    assert response.status_code == 409
    assert response.json()["code"] == "draft_has_ambiguities"
```

- [x] **Step 2: Run confirmation tests and verify RED**

Run: `.venv/bin/pytest backend/tests/reminders/api/test_voice_confirmation.py -q`

Expected: FAIL because `ReminderRule` and the confirm endpoint do not exist.

- [x] **Step 3: Add the minimal reminder rule and transactional confirmation**

```python
class ReminderRule(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    title = models.CharField(max_length=200)
    timezone = models.CharField(max_length=64)
    schedule_json = models.JSONField()
    conditions_json = models.JSONField(default=dict)
    severity = models.CharField(max_length=32)
    enabled = models.BooleanField(default=True)
    source_draft = models.OneToOneField(ReminderDraft, on_delete=models.PROTECT)
```

The confirm view must use `transaction.atomic()` and `select_for_update()`, reject expired, foreign, or ambiguous drafts, and return the existing rule on repeat confirmation.

- [x] **Step 4: Create migrations and verify GREEN**

Run: `.venv/bin/python backend/manage.py makemigrations reminders && .venv/bin/pytest backend/tests/reminders/api/test_voice_confirmation.py -q`

Expected: `2 passed`.

- [x] **Step 5: Run the full backend suite and commit**

Run: `.venv/bin/pytest backend -q`

Expected: all backend tests pass.

```bash
git add backend
git commit -m "feat: confirm voice drafts idempotently"
```

## Task 5: Flutter iPhone Application Foundation

**Files:**
- Create: `app/pubspec.yaml`
- Create: `app/lib/main.dart`
- Create: `app/lib/features/voice_reminders/domain/reminder_draft.dart`
- Create: `app/lib/features/voice_reminders/data/voice_draft_api.dart`
- Create: `app/lib/features/voice_reminders/presentation/voice_draft_screen.dart`
- Test: `app/test/voice_draft_screen_test.dart`

- [x] **Step 1: Create the Flutter project metadata**

`pubspec.yaml` must target Dart `>=3.5.0 <4.0.0` and include only `flutter`, `http`, and `flutter_test` for this phase.

- [x] **Step 2: Write the failing widget test**

```dart
testWidgets('voice draft requires explicit confirmation', (tester) async {
  await tester.pumpWidget(MaterialApp(home: VoiceDraftScreen(draft: sampleDraft)));
  expect(find.text('结构化提醒草稿'), findsOneWidget);
  expect(find.text('明天 07:30'), findsOneWidget);
  expect(find.widgetWithText(FilledButton, '确认创建'), findsOneWidget);
});
```

- [x] **Step 3: Run the widget test and verify RED**

Run: `cd app && flutter test test/voice_draft_screen_test.dart`

Expected: FAIL because the screen does not exist. If `flutter` is unavailable, record the environment blocker and continue creating the source without claiming a passing Flutter build.

- [x] **Step 4: Implement the minimal domain model, HTTP client, and screen**

The screen shows the transcript, title, local time, weather precheck, severity, ambiguities, a secondary edit action, and one primary confirmation action. `VoiceDraftApi` receives `baseUrl` in its constructor so an iPhone can use the Mac LAN address instead of `localhost`.

- [ ] **Step 5: Run Flutter analyze and tests**

Run: `cd app && flutter analyze && flutter test`

Expected: zero analyzer errors and all widget tests pass once Flutter SDK is installed.

Blocked on 2026-08-03: the machine has no `flutter` or `dart` command. Source structure and `pubspec.yaml` were validated, but analyzer and Widget tests were not executed.

- [x] **Step 6: Commit the Flutter foundation**

```bash
git add app
git commit -m "feat: add Flutter voice draft confirmation shell"
```

## Task 6: Docker Compose Local Infrastructure

**Files:**
- Create: `compose.yaml`
- Create: `backend/Dockerfile`
- Create: `.env.example`
- Create: `.gitignore`
- Create: `Makefile`
- Create: `README.md`

- [x] **Step 1: Add container configuration**

`compose.yaml` must define PostgreSQL 16, Redis 7, MinIO, Django API, Celery worker, and Celery beat. Health checks gate dependent services. No production credentials are committed; `.env.example` contains local-only values.

- [x] **Step 2: Add repeatable development commands**

```make
install:
	python3 -m venv .venv
	.venv/bin/python -m pip install -r backend/requirements/dev.txt

test-backend:
	.venv/bin/pytest backend -q

run-backend:
	.venv/bin/python backend/manage.py runserver 0.0.0.0:8000

compose-up:
	docker compose up --build
```

- [x] **Step 3: Validate configuration**

Run: `docker compose config`

Expected: valid composed configuration. If Docker is unavailable, record the environment blocker and verify YAML syntax with the available parser.

Verified on 2026-08-03 with the system Ruby YAML parser: all six services and aliases parse correctly. Docker Compose execution remains blocked because the machine has no `docker` command.

- [x] **Step 4: Document Mac-to-iPhone access**

README must explain that the iPhone and Mac share a LAN, the app uses `http://<MAC_LAN_IP>:8000` only in Debug, Django `ALLOWED_HOSTS` includes the explicit LAN IP, and production always uses HTTPS.

- [x] **Step 5: Commit local infrastructure**

```bash
git add compose.yaml backend/Dockerfile .env.example .gitignore Makefile README.md
git commit -m "build: add local development infrastructure"
```

## Task 7: Phase Verification And Handoff

**Files:**
- Modify: `docs/superpowers/plans/2026-08-03-foundation-voice-draft-mvp.md`

- [x] **Step 1: Run backend verification**

Run: `.venv/bin/pytest backend -q`

Expected: all tests pass.

- [x] **Step 2: Run Django deployment checks**

Run: `.venv/bin/python backend/manage.py check && .venv/bin/python backend/manage.py makemigrations --check --dry-run`

Expected: no system-check errors and no missing migrations.

- [x] **Step 3: Run Flutter and Compose verification when tools exist**

Run: `cd app && flutter analyze && flutter test`, then `docker compose config`.

Expected: all pass. Missing Flutter or Docker must be reported as an environment prerequisite, not treated as a successful verification.

Environment result on 2026-08-03: backend verification passed; Flutter and Docker commands are unavailable and therefore were not claimed as passing.

- [x] **Step 4: Exercise the API manually**

Create a local user, authenticate through the test client or development token flow, submit the agreed Chinese transcript, verify a pending draft is returned, confirm it twice, and verify both confirmations reference the same reminder UUID.

- [x] **Step 5: Update checklist and commit phase completion**

Mark only executed steps complete, then run `git diff --check` and `git status --short`.

```bash
git add docs/superpowers/plans/2026-08-03-foundation-voice-draft-mvp.md
git commit -m "docs: record voice draft MVP verification"
```

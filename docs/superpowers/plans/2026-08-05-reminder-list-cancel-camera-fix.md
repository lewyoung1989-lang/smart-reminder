# Reminder List, Cancellation, and Camera Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an owner-scoped reminder history with pending, expired, and cancelled states, keep server cancellation consistent with iPhone local notifications, and stop camera capture from terminating the iOS app.

**Architecture:** Django stores indexed `scheduled_at` and nullable `cancelled_at` values on each `ReminderRule`, computes lifecycle state at request time, and exposes cursor-paginated list and idempotent cancel endpoints. Flutter keeps reminder API/domain types separate from draft creation, presents three independently loaded tab lists, and cancels the server record before cancelling the corresponding local notification. Camera failure is handled at the screen boundary while iOS declares its camera purpose in `Info.plist`.

**Tech Stack:** Python 3.13, Django 5.2, Django REST Framework, PostgreSQL 16, pytest, Flutter/Dart, `flutter_local_notifications`, `image_picker`, iOS/Xcode.

---

## File Map

- `backend/apps/reminders/models.py`: indexed schedule and cancellation persistence.
- `backend/apps/reminders/migrations/0004_reminderrule_lifecycle.py`: schema change plus deterministic historical schedule backfill.
- `backend/apps/reminders/api/serializers.py`: reminder list response serialization.
- `backend/apps/reminders/api/views.py`: status filtering, stable cursor ordering, and transactional cancellation.
- `backend/apps/reminders/api/urls.py`: list and cancel routes.
- `backend/tests/reminders/migrations/test_reminder_rule_lifecycle.py`: aware and naive historical migration cases.
- `backend/tests/reminders/api/test_reminder_list.py`: authentication, ownership, lifecycle boundary, ordering, pagination, and invalid status.
- `backend/tests/reminders/api/test_reminder_cancel.py`: cancellation success, idempotency, expiry conflict, and ownership.
- `backend/tests/reminders/api/test_voice_confirmation.py`: confirmation writes `scheduled_at`.
- `app/lib/features/reminders/domain/reminder.dart`: reminder lifecycle values and page model.
- `app/lib/features/reminders/data/reminder_api.dart`: same-origin cursor list and cancel HTTP client.
- `app/lib/features/reminders/presentation/reminder_home_screen.dart`: list-first tabs, refresh/pagination, creation return, and cancellation interaction.
- `app/lib/features/reminder_drafts/presentation/reminder_composer_screen.dart`: return a creation outcome to its caller.
- `app/lib/platform/notifications/reminder_notification_scheduler.dart`: schedule/cancel contract.
- `app/lib/platform/notifications/local_notification_scheduler.dart`: stable-ID cancellation implementation.
- `app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart`: recover from camera invocation errors.
- `app/lib/main.dart`: compose the new reminder API and home screen.
- `app/ios/Runner/Info.plist`: non-empty camera usage description.
- `app/test/reminder_api_test.dart`: reminder list, same-origin cursor, and cancellation HTTP tests.
- `app/test/reminder_home_screen_test.dart`: tab state, refresh, pagination, creation, cancellation, and stale-response tests.
- `app/test/local_notification_scheduler_test.dart`: stable notification cancellation tests.
- `app/test/medicine_ocr_screen_test.dart`: camera error and user-cancel behavior tests.
- `backend/tests/development/test_flutter_wrapper.py`: iOS camera privacy key regression.

### Task 1: Camera Privacy and Recoverable Capture Errors

**Files:**
- Modify: `app/ios/Runner/Info.plist`
- Modify: `app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart`
- Modify: `app/test/medicine_ocr_screen_test.dart`
- Modify: `backend/tests/development/test_flutter_wrapper.py`

- [ ] **Step 1: Write failing privacy and widget tests**

Add a wrapper contract that parses `Info.plist` and asserts:

```python
def test_ios_declares_camera_usage_description():
    plist = plistlib.loads((APP_ROOT / "ios/Runner/Info.plist").read_bytes())
    assert plist["NSCameraUsageDescription"].strip()
```

Add widget tests where `capture` throws and returns `null`:

```dart
testWidgets('camera failure stays on capture screen with guidance', (tester) async {
  await tester.pumpWidget(buildScreen(capture: (_) async => throw Exception('denied')));
  await tester.tap(find.text('拍摄药盒正面'));
  await tester.pump();
  expect(find.text('无法打开相机，请检查相机权限后重试'), findsOneWidget);
  expect(find.text('拍摄药盒正面'), findsOneWidget);
});

testWidgets('cancelling camera does not show an error', (tester) async {
  await tester.pumpWidget(buildScreen(capture: (_) async => null));
  await tester.tap(find.text('拍摄药盒正面'));
  await tester.pump();
  expect(find.text('无法打开相机，请检查相机权限后重试'), findsNothing);
});
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
.venv/bin/pytest backend/tests/development/test_flutter_wrapper.py -q
cd app && flutter test test/medicine_ocr_screen_test.dart
```

Expected: the privacy test fails because `NSCameraUsageDescription` is absent, and the widget test reports the uncaught capture exception.

- [ ] **Step 3: Add the privacy string and capture boundary**

Add to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>用于拍摄药盒和有效期，识别结果需由你确认后才会加入药箱。</string>
```

Wrap `widget.capture(kind)`:

```dart
try {
  final bytes = await widget.capture(kind);
  if (!mounted || bytes == null) return;
  setState(() {
    if (kind == 'front') _frontBytes = bytes;
    if (kind == 'expiry') _expiryBytes = bytes;
    _error = null;
  });
} catch (_) {
  if (!mounted) return;
  setState(() => _error = '无法打开相机，请检查相机权限后重试');
}
```

- [ ] **Step 4: Re-run focused tests**

Expected: both commands pass.

- [ ] **Step 5: Commit**

```bash
git add app/ios/Runner/Info.plist app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart app/test/medicine_ocr_screen_test.dart backend/tests/development/test_flutter_wrapper.py
git commit -m "fix: handle iPhone camera permission failures"
```

### Task 2: Reminder Lifecycle Persistence and Migration

**Files:**
- Modify: `backend/apps/reminders/models.py`
- Create: `backend/apps/reminders/migrations/0004_reminderrule_lifecycle.py`
- Create: `backend/tests/reminders/migrations/test_reminder_rule_lifecycle.py`
- Modify: `backend/tests/reminders/api/test_voice_confirmation.py`

- [ ] **Step 1: Write failing lifecycle persistence tests**

Extend confirmation coverage:

```python
rule = ReminderRule.objects.get(owner=user)
assert rule.scheduled_at.isoformat() == "2026-08-03T23:30:00+00:00"
assert rule.cancelled_at is None
```

Add migration-executor cases for an aware `2026-08-04T07:30:00+08:00` and a naive `2026-08-04T07:30:00` with `timezone="Asia/Shanghai"`; both must become the same aware instant after migrating to `0004_reminderrule_lifecycle`.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
.venv/bin/pytest backend/tests/reminders/api/test_voice_confirmation.py backend/tests/reminders/migrations/test_reminder_rule_lifecycle.py -q
```

Expected: failure because the model and migration do not contain the lifecycle fields.

- [ ] **Step 3: Add model fields and backfill migration**

Use:

```python
scheduled_at = models.DateTimeField(db_index=True)
cancelled_at = models.DateTimeField(null=True, blank=True)
```

The migration first adds nullable fields, parses every `schedule_json["local_datetime"]` with `datetime.fromisoformat`, applies `zoneinfo.ZoneInfo(rule.timezone)` to naive values, converts through Django timezone handling, bulk-updates rows, alters `scheduled_at` to non-null/indexed, and fails with a `RuntimeError` containing the rule ID when parsing is impossible.

- [ ] **Step 4: Write `scheduled_at` on confirmation**

Pass the validated Pydantic datetime directly when creating the rule:

```python
scheduled_at=draft_data.schedule.local_datetime,
```

- [ ] **Step 5: Run migration and confirmation tests**

Run:

```bash
.venv/bin/pytest backend/tests/reminders/api/test_voice_confirmation.py backend/tests/reminders/migrations/test_reminder_rule_lifecycle.py -q
.venv/bin/python backend/manage.py makemigrations --check --dry-run
```

Expected: tests pass and Django prints `No changes detected`.

- [ ] **Step 6: Commit**

```bash
git add backend/apps/reminders/models.py backend/apps/reminders/migrations/0004_reminderrule_lifecycle.py backend/apps/reminders/api/views.py backend/tests/reminders/api/test_voice_confirmation.py backend/tests/reminders/migrations/test_reminder_rule_lifecycle.py
git commit -m "feat: persist reminder lifecycle timestamps"
```

### Task 3: Reminder List and Cancel APIs

**Files:**
- Modify: `backend/apps/reminders/api/serializers.py`
- Modify: `backend/apps/reminders/api/views.py`
- Modify: `backend/apps/reminders/api/urls.py`
- Create: `backend/tests/reminders/api/test_reminder_list.py`
- Create: `backend/tests/reminders/api/test_reminder_cancel.py`

- [ ] **Step 1: Write failing list API tests**

Create reminders around a frozen `now` and assert:

```python
response = api_client.get("/api/v1/reminders", {"status": "pending"})
assert response.status_code == 200
assert [item["title"] for item in response.json()["results"]] == [
    "next",
    "later",
]
assert all(item["status"] == "pending" for item in response.json()["results"])
```

Separate tests must prove expired descending order, cancelled descending order, the exact `scheduled_at == now` boundary is expired, default status is pending, anonymous access is `401`, another owner's data is absent, invalid status is `400`, and 51 rows produce pages of 50 and 1 without duplicate IDs.

- [ ] **Step 2: Run list tests and verify 404 failures**

Run: `.venv/bin/pytest backend/tests/reminders/api/test_reminder_list.py -q`

Expected: failures because `/api/v1/reminders` is not routed.

- [ ] **Step 3: Implement status-specific cursor pagination**

Create a serializer with read-only fields `id`, `title`, `timezone`, `scheduled_at`, `severity`, `cancelled_at`, plus a `get_status` method using a single `now` supplied through serializer context.

Use three pagination classes with `page_size = 50` and stable orderings:

```python
class PendingReminderPagination(CursorPagination):
    page_size = 50
    ordering = ("scheduled_at", "id")

class ExpiredReminderPagination(CursorPagination):
    page_size = 50
    ordering = ("-scheduled_at", "id")

class CancelledReminderPagination(CursorPagination):
    page_size = 50
    ordering = ("-cancelled_at", "id")
```

The view validates `status` against `pending`, `expired`, and `cancelled`, filters `owner=request.user`, applies the matching predicate and paginator, and passes the same `now` to the serializer.

- [ ] **Step 4: Run list API tests**

Expected: all list tests pass.

- [ ] **Step 5: Write failing cancellation tests**

Assert pending cancellation sets `enabled=False` and `cancelled_at`, a second POST preserves the original timestamp, exact-boundary expired cancellation returns:

```json
{"code": "reminder_expired", "detail": "提醒时间已过，不能取消"}
```

with status `409`, and both missing/cross-owner IDs return `404`.

- [ ] **Step 6: Implement owner-scoped transactional cancellation**

Inside `transaction.atomic()`, `select_for_update().get(id=reminder_id, owner=request.user)`. Return the existing cancelled representation when already disabled with `cancelled_at`; reject `scheduled_at <= now`; otherwise set both fields and save only `enabled` and `cancelled_at`.

- [ ] **Step 7: Run all reminder API tests**

Run: `.venv/bin/pytest backend/tests/reminders/api -q`

Expected: all reminder API tests pass.

- [ ] **Step 8: Commit**

```bash
git add backend/apps/reminders/api backend/tests/reminders/api/test_reminder_list.py backend/tests/reminders/api/test_reminder_cancel.py
git commit -m "feat: add reminder list and cancel APIs"
```

### Task 4: Flutter Reminder Domain and HTTP Client

**Files:**
- Create: `app/lib/features/reminders/domain/reminder.dart`
- Create: `app/lib/features/reminders/data/reminder_api.dart`
- Create: `app/test/reminder_api_test.dart`

- [ ] **Step 1: Write failing client tests**

Tests cover default and explicit status query, parsing `scheduled_at`/`cancelled_at`, parsing `next`, rejecting a cursor whose scheme/host/port differs from the configured API base, sending `POST /api/v1/reminders/{id}/cancel`, and mapping a `409` response to `ReminderApiException` without mutating client state.

- [ ] **Step 2: Run and verify missing-library failure**

Run: `cd app && flutter test test/reminder_api_test.dart`

Expected: compilation fails because the reminder domain and client files do not exist.

- [ ] **Step 3: Implement typed lifecycle models**

Define:

```dart
enum ReminderStatus { pending, expired, cancelled }

class Reminder {
  const Reminder({required this.id, required this.title, required this.timezone,
    required this.scheduledAt, required this.severity, required this.status,
    required this.cancelledAt});
  factory Reminder.fromJson(Map<String, dynamic> json) { /* strict field mapping */ }
}

class ReminderPage {
  const ReminderPage({required this.reminders, required this.nextPage});
  final List<Reminder> reminders;
  final Uri? nextPage;
}
```

- [ ] **Step 4: Implement list and cancel requests**

`ReminderApi.list({status, pageUrl})` must resolve `/api/v1/reminders?status=...`, verify same-origin cursors, send the Bearer token, and accept only `200`. `cancel(id)` POSTs to the cancel route and accepts only `200`. All other responses throw `ReminderApiException(statusCode, body)`.

- [ ] **Step 5: Run client tests**

Expected: all `reminder_api_test.dart` tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/reminders app/test/reminder_api_test.dart
git commit -m "feat: add Flutter reminder API client"
```

### Task 5: Local Notification Cancellation

**Files:**
- Modify: `app/lib/platform/notifications/reminder_notification_scheduler.dart`
- Modify: `app/lib/platform/notifications/local_notification_scheduler.dart`
- Modify: `app/test/local_notification_scheduler_test.dart`
- Modify: `app/test/reminder_confirmation_notification_test.dart`

- [ ] **Step 1: Write failing stable-ID cancellation tests**

Record gateway cancellations and assert scheduling and cancellation use the same integer:

```dart
await scheduler.schedule(reminderId: 'reminder-1', draft: draftAt(future));
await scheduler.cancel(reminderId: 'reminder-1');
expect(gateway.cancelled.single, gateway.scheduled.single.id);
expect(gateway.permissionRequestCount, 1);
```

- [ ] **Step 2: Run and verify interface compilation failure**

Run: `cd app && flutter test test/local_notification_scheduler_test.dart test/reminder_confirmation_notification_test.dart`

Expected: compilation fails until test doubles and production classes implement `cancel`.

- [ ] **Step 3: Extend scheduler and gateway contracts**

Add `Future<void> cancel({required String reminderId})` to `ReminderNotificationScheduler`, `Future<void> cancel({required int id})` to `LocalNotificationGateway`, and implement:

```dart
@override
Future<void> cancel({required String reminderId}) async {
  try {
    await gateway.cancel(id: _stableNotificationId(reminderId));
  } catch (_) {
    throw const NotificationCancellationFailed();
  }
}
```

The Flutter gateway delegates to `_plugin.cancel(id: id)`. Cancellation must not request permissions.

- [ ] **Step 4: Run notification tests**

Expected: focused notification tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/platform/notifications app/test/local_notification_scheduler_test.dart app/test/reminder_confirmation_notification_test.dart
git commit -m "feat: cancel local reminder notifications"
```

### Task 6: Reminder Home Tabs, Creation Return, and Cancellation UX

**Files:**
- Create: `app/lib/features/reminders/presentation/reminder_home_screen.dart`
- Create: `app/test/reminder_home_screen_test.dart`
- Modify: `app/lib/features/reminder_drafts/presentation/reminder_composer_screen.dart`
- Modify: `app/test/reminder_composer_screen_test.dart`
- Modify: `app/test/reminder_confirmation_notification_test.dart`
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Write failing tab/list state tests**

Widget tests assert the labels `待提醒`, `已过期`, and `已取消`; pending loads first; tapping each tab issues its own status request; empty/loading/first-page-error states render per tab; pull refresh replaces results; reaching the end appends the next cursor page; page errors preserve current rows and expose `重试加载`; and an older response resolving after a newer refresh cannot overwrite it.

- [ ] **Step 2: Run and verify missing-screen failure**

Run: `cd app && flutter test test/reminder_home_screen_test.dart`

Expected: compilation fails because `ReminderHomeScreen` is absent.

- [ ] **Step 3: Implement independently cached tab state**

Use a `DefaultTabController(length: 3)` and one state object per `ReminderStatus` holding `items`, `nextPage`, `loading`, `loadingMore`, `firstPageFailed`, `loadMoreFailed`, and `generation`. Increment generation before each first-page request and ignore completions whose captured generation no longer matches.

Each list uses `RefreshIndicator`, `AlwaysScrollableScrollPhysics`, stable row keys, local date/time formatting, and a bottom progress/retry row. Pending uses ascending server order and a cancel icon; expired/cancelled are read-only.

- [ ] **Step 4: Write failing creation-return test**

Tap the App Bar add icon, complete a stub composer, and assert the route pops with a `ReminderCreationResult`; pending reloads and a SnackBar distinguishes `notificationScheduled=true` from `false`.

- [ ] **Step 5: Return a typed creation result from composer**

After server confirmation and notification scheduling, call:

```dart
Navigator.of(context).pop(
  ReminderCreationResult(
    reminderId: reminderId,
    notificationScheduled: scheduler != null,
  ),
);
```

On `ReminderNotificationException`, pop the same reminder ID with `notificationScheduled: false`. When the composer is used as a standalone test root and cannot pop, preserve its existing SnackBar behavior.

- [ ] **Step 6: Write failing cancellation interaction tests**

Assert the pending row opens a confirmation dialog containing the title and `取消后不会再通知`; confirm calls server cancellation first, then local cancellation; on success the row leaves pending and cancelled reloads. Server failure must not call the local scheduler. Local failure after server success must still move the row and show `提醒已取消，但手机通知可能仍存在`. Disable the row action while cancellation is running.

- [ ] **Step 7: Implement server-first cancellation**

Call `cancelReminder(reminder.id)`, then `notificationScheduler.cancel(reminderId: reminder.id)`. Refresh pending and invalidate/reload cancelled after server success. Catch `NotificationCancellationFailed` separately for the partial-failure message; catch API/network errors before local cancellation and retain the pending row.

- [ ] **Step 8: Compose the reminder home in `main.dart`**

Instantiate `ReminderApi` with the same base URL and token, close it in `dispose`, and replace the reminder shell child with `ReminderHomeScreen`. Its add-route builds the existing composer with `ReminderDraftApi` functions and the same notification scheduler.

- [ ] **Step 9: Run all relevant widget tests**

Run:

```bash
cd app && flutter test test/reminder_home_screen_test.dart test/reminder_composer_screen_test.dart test/reminder_confirmation_notification_test.dart
```

Expected: all pass with no pending timers or uncaught exceptions.

- [ ] **Step 10: Commit**

```bash
git add app/lib/main.dart app/lib/features/reminders/presentation app/lib/features/reminder_drafts/presentation/reminder_composer_screen.dart app/test/reminder_home_screen_test.dart app/test/reminder_composer_screen_test.dart app/test/reminder_confirmation_notification_test.dart
git commit -m "feat: add reminder lifecycle home"
```

### Task 7: Verification, Publication, Deployment, and iPhone Acceptance

**Files:**
- Verify all changed files.
- Update: `docs/superpowers/plans/2026-08-05-reminder-list-cancel-camera-fix.md` checkbox state.

- [ ] **Step 1: Run complete local backend verification**

```bash
.venv/bin/pytest backend -q
.venv/bin/python backend/manage.py check
.venv/bin/python backend/manage.py makemigrations --check --dry-run
```

Expected: every test passes, system check reports no issues, and no migration changes are detected.

- [ ] **Step 2: Run complete Flutter verification**

```bash
cd app
flutter test
flutter analyze
flutter build ios --simulator
```

Expected: tests and analysis pass, and the Simulator app builds successfully.

- [ ] **Step 3: Review diff and publish `main`**

```bash
git status --short
git diff --check
git log --oneline --decorate -8
git push origin main
```

Expected: no uncommitted implementation changes, no whitespace errors, and GitHub `main` reaches the verified local SHA.

- [ ] **Step 4: Deploy the exact GitHub SHA to Tencent Cloud**

On the server, fetch `main`, verify the checkout matches the exact SHA, then run:

```bash
cd /opt/smart-reminder/app
deploy/tencent/scripts/deploy.sh EXACT_FULL_SHA /opt/smart-reminder/shared/.env.production
```

Expected: migrations complete, services are healthy, and `https://aipupu.cloud/api/v1/health` returns `200`.

- [ ] **Step 5: Run production API acceptance**

Using a non-echoed temporary Bearer token, create and confirm two near-future reminders. Verify pending listing order, cancel one twice, verify it moves to cancelled with the same `cancelled_at`, wait for the other timestamp, and verify it moves to expired. Verify another identity cannot list or cancel either record.

- [ ] **Step 6: Build, install, and verify signed iPhone Release**

Build with the production API URL and a non-echoed test token, install to the connected iPhone, and verify: list-first reminder page, creation returning to pending, notification delivery, cancellation suppressing notification, natural move to expired, camera permission prompt, successful capture, and no TCC termination.

- [ ] **Step 7: Remove temporary acceptance identity**

After device acceptance, revoke its token and delete the temporary user and records unless the installed build must remain usable for an agreed follow-up. Never print or commit the token.

## Self-Review

- Spec coverage: persistence, migration, owner isolation, three states, boundary semantics, stable cursor pagination, idempotent cancellation, server-first local cancellation, list-first UX, creation refresh, error states, stale-response isolation, camera privacy, deployment, and iPhone acceptance each map to a task above.
- Placeholder scan: the plan contains no `TBD`, deferred implementation marker, unspecified error-handling step, or undefined task reference.
- Type consistency: `ReminderStatus`, `Reminder`, `ReminderPage`, `ReminderApi`, `ReminderCreationResult`, `ReminderNotificationScheduler.cancel`, `LocalNotificationGateway.cancel`, `scheduled_at`, and `cancelled_at` are named consistently across tasks.

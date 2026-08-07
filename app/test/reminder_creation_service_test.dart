import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminder_drafts/application/reminder_creation_service.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';

import 'support/test_fixtures.dart';

class SynchronousNotificationScheduler
    implements ReminderNotificationScheduler {
  SynchronousNotificationScheduler({this.error});

  Object? error;
  final requests = <({String reminderId, ReminderDraft draft})>[];

  @override
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  }) {
    requests.add((reminderId: reminderId, draft: draft));
    if (error case final value?) throw value;
    return Future.value();
  }

  @override
  Future<void> cancel({required String reminderId}) => Future.value();
}

void main() {
  test('retries scheduling after permission denial without reconfirming',
      () async {
    var confirmationCount = 0;
    final scheduler = RecordingNotificationScheduler(
      error: const NotificationPermissionDenied(),
    );
    final service = ReminderCreationService(
      confirmDraft: (_) async {
        confirmationCount += 1;
        return 'reminder-1';
      },
      notificationScheduler: scheduler,
    );

    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationNotScheduled,
    );

    scheduler.error = null;

    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationScheduled,
    );
    expect(confirmationCount, 1);
    expect(scheduler.requests, hasLength(2));
  });

  test('evicts a reminder without a notification scheduler', () async {
    var confirmationCount = 0;
    final service = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-${++confirmationCount}',
    );

    expect(await service.confirm(testDraft), CreationOutcome.created);
    expect(await service.confirm(testDraft), CreationOutcome.created);
    expect(confirmationCount, 2);
  });

  test('shares an in-flight confirmation for the same draft', () async {
    final confirmation = Completer<String>();
    var confirmationCount = 0;
    final service = ReminderCreationService(
      confirmDraft: (_) {
        confirmationCount += 1;
        return confirmation.future;
      },
    );

    final first = service.confirm(testDraft);
    final second = service.confirm(testDraft);

    await Future<void>.microtask(() {});
    expect(confirmationCount, 1);
    confirmation.complete('reminder-1');
    expect(
      await Future.wait([first, second]),
      [CreationOutcome.created, CreationOutcome.created],
    );
  });

  test('returns notificationNotScheduled for an invalid schedule', () async {
    final scheduler = RecordingNotificationScheduler(
      error: const InvalidNotificationSchedule(),
    );
    final service = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-1',
      notificationScheduler: scheduler,
    );

    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationNotScheduled,
    );
  });

  test('retries after a synchronously thrown notification exception', () async {
    var confirmationCount = 0;
    final scheduler = SynchronousNotificationScheduler(
      error: const NotificationPermissionDenied(),
    );
    final service = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-${++confirmationCount}',
      notificationScheduler: scheduler,
    );

    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationNotScheduled,
    );

    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationNotScheduled,
    );

    scheduler.error = null;

    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationScheduled,
    );
    expect(confirmationCount, 1);
    expect(scheduler.requests, hasLength(3));
  });

  test('evicts a reminder after successfully scheduling its notification',
      () async {
    var confirmationCount = 0;
    final scheduler = RecordingNotificationScheduler();
    final service = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-${++confirmationCount}',
      notificationScheduler: scheduler,
    );

    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationScheduled,
    );
    expect(
      await service.confirm(testDraft),
      CreationOutcome.notificationScheduled,
    );

    expect(confirmationCount, 2);
    expect(scheduler.requests, hasLength(2));
  });

  test('shares an in-flight notification schedule for the same draft',
      () async {
    final scheduler = RecordingNotificationScheduler();
    final confirmation = Completer<String>();
    final service = ReminderCreationService(
      confirmDraft: (_) => confirmation.future,
      notificationScheduler: scheduler,
    );

    final first = service.confirm(testDraft);
    final second = service.confirm(testDraft);

    confirmation.complete('reminder-1');
    expect(
      await Future.wait([first, second]),
      [
        CreationOutcome.notificationScheduled,
        CreationOutcome.notificationScheduled,
      ],
    );
    expect(scheduler.requests, hasLength(1));
  });

  test('wraps unexpected scheduler errors after confirming the reminder',
      () async {
    final service = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-1',
      notificationScheduler: RecordingNotificationScheduler(
        error: StateError('scheduler unavailable'),
      ),
    );

    await expectLater(
      service.confirm(testDraft),
      throwsA(
        isA<ReminderNotificationSchedulingException>()
            .having((error) => error.cause, 'cause', isA<StateError>()),
      ),
    );
  });

  test('propagates backend confirmation errors', () async {
    final service = ReminderCreationService(
      confirmDraft: (_) async => throw StateError('backend unavailable'),
    );

    await expectLater(
      service.confirm(testDraft),
      throwsA(isA<StateError>()),
    );
  });
}

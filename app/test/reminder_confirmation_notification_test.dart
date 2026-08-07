import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminder_drafts/application/reminder_creation_service.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/presentation/reminder_composer_screen.dart';
import 'package:smart_reminder_app/features/reminders/domain/reminder.dart'
    show ReminderCreationResult;
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';

import 'support/test_fixtures.dart';

void main() {
  final draft = ReminderDraft(
    id: 'draft-1',
    title: '喝水',
    scheduledAt: DateTime(2026, 8, 4, 10, 1),
    timezone: 'Asia/Shanghai',
    severity: ReminderSeverity.notification,
    weatherMessage: null,
    ambiguities: const [],
    parserSource: 'local',
  );

  Future<void> openDraftAndConfirm(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '1分钟后提醒我喝水');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirmation schedules one local notification', (tester) async {
    final scheduler = RecordingNotificationScheduler();
    final creationService = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-1',
      notificationScheduler: scheduler,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderComposerScreen(
          createDraft: (_) async => draft,
          reminderCreationService: creationService,
          now: DateTime(2026, 8, 4, 10),
        ),
      ),
    );

    await openDraftAndConfirm(tester);

    expect(scheduler.requests, hasLength(1));
    expect(scheduler.requests.single.reminderId, 'reminder-1');
    expect(scheduler.requests.single.draft.title, '喝水');
    expect(find.text('提醒已创建，通知已安排'), findsNothing);
  });

  testWidgets('successful confirmation returns one terminal creation result',
      (tester) async {
    final scheduler = RecordingNotificationScheduler();
    var confirmationCount = 0;
    ReminderCreationResult? returnedResult;
    final backendConfirmation = Completer<String>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              returnedResult = await Navigator.of(context).push(
                MaterialPageRoute<ReminderCreationResult>(
                  builder: (_) => ReminderComposerScreen(
                    createDraft: (_) async => draft,
                    confirmDraft: (_) {
                      confirmationCount += 1;
                      return backendConfirmation.future;
                    },
                    notificationScheduler: scheduler,
                    now: DateTime(2026, 8, 4, 10),
                  ),
                ),
              );
            },
            child: const Text('打开创建'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开创建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1分钟后提醒我喝水');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, '确认');
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();

    expect(confirmationCount, 1);

    backendConfirmation.complete('reminder-1');
    await tester.pumpAndSettle();

    expect(
      returnedResult,
      isA<ReminderCreationResult>()
          .having((result) => result.reminderId, 'reminderId', 'reminder-1')
          .having(
            (result) => result.notificationScheduled,
            'notificationScheduled',
            isTrue,
          ),
    );
    expect(scheduler.requests, hasLength(1));
  });

  testWidgets('permission denial reports a warning without reconfirming',
      (tester) async {
    final scheduler = RecordingNotificationScheduler()
      ..error = const NotificationPermissionDenied();
    var confirmationCount = 0;
    final creationService = ReminderCreationService(
      confirmDraft: (_) async {
        confirmationCount += 1;
        return 'reminder-1';
      },
      notificationScheduler: scheduler,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderComposerScreen(
          createDraft: (_) async => draft,
          reminderCreationService: creationService,
          now: DateTime(2026, 8, 4, 10),
        ),
      ),
    );

    await openDraftAndConfirm(tester);
    expect(find.text('提醒已创建，但手机通知未安排'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(confirmationCount, 1);
    expect(scheduler.requests, hasLength(2));
  });

  testWidgets('unexpected scheduling error reports reminder creation',
      (tester) async {
    final scheduler = RecordingNotificationScheduler()
      ..error = StateError('scheduler unavailable');
    final creationService = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-1',
      notificationScheduler: scheduler,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderComposerScreen(
          createDraft: (_) async => draft,
          reminderCreationService: creationService,
          now: DateTime(2026, 8, 4, 10),
        ),
      ),
    );

    await openDraftAndConfirm(tester);

    expect(find.text('提醒已创建，但手机通知未安排'), findsOneWidget);
    expect(find.text('创建失败，请稍后重试'), findsNothing);
  });
}

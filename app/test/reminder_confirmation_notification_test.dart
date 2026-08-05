import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/presentation/reminder_composer_screen.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';


class RecordingNotificationScheduler implements ReminderNotificationScheduler {
  final requests = <({String reminderId, ReminderDraft draft})>[];
  Object? error;

  Future<void> cancel({required String reminderId}) async {}

  @override
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  }) async {
    requests.add((reminderId: reminderId, draft: draft));
    if (error case final value?) throw value;
  }
}


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
    await tester.tap(find.widgetWithText(FilledButton, '解析提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认创建'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirmation schedules one local notification', (tester) async {
    final scheduler = RecordingNotificationScheduler();
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderComposerScreen(
          createDraft: (_) async => draft,
          confirmDraft: (_) async => 'reminder-1',
          notificationScheduler: scheduler,
          now: DateTime(2026, 8, 4, 10),
        ),
      ),
    );

    await openDraftAndConfirm(tester);

    expect(scheduler.requests, hasLength(1));
    expect(scheduler.requests.single.reminderId, 'reminder-1');
    expect(scheduler.requests.single.draft.title, '喝水');
    expect(find.text('提醒已创建，通知已安排'), findsOneWidget);
  });

  testWidgets('permission denial reports a warning without reconfirming', (tester) async {
    final scheduler = RecordingNotificationScheduler()
      ..error = const NotificationPermissionDenied();
    var confirmationCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderComposerScreen(
          createDraft: (_) async => draft,
          confirmDraft: (_) async {
            confirmationCount += 1;
            return 'reminder-1';
          },
          notificationScheduler: scheduler,
          now: DateTime(2026, 8, 4, 10),
        ),
      ),
    );

    await openDraftAndConfirm(tester);
    expect(find.text('提醒已创建，但手机通知未安排'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认创建'));
    await tester.pumpAndSettle();

    expect(confirmationCount, 1);
    expect(scheduler.requests, hasLength(2));
  });
}

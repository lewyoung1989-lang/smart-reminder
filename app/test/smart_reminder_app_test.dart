import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/config/app_config.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/main.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';

class NoopScheduler implements ReminderNotificationScheduler {
  @override
  Future<void> cancel({required String reminderId}) async {}

  @override
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  }) async {}
}

void main() {
  testWidgets('reminder destination opens the lifecycle list first',
      (tester) async {
    await tester.pumpWidget(
      SmartReminderApp(
        config: const AppConfig(
          apiBaseUrl: 'http://127.0.0.1:1',
          apiAccessToken: 'test-token',
        ),
        notificationScheduler: NoopScheduler(),
      ),
    );
    await tester.pump();

    expect(find.text('待提醒'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('提醒内容'), findsNothing);
  });
}

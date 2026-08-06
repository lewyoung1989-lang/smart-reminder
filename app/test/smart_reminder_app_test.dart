import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/config/app_config.dart';
import 'package:smart_reminder_app/features/auth/data/token_store.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';
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

class EmptyTokenStore implements TokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<AuthTokens?> read() async => null;

  @override
  Future<void> write(AuthTokens tokens) async {}
}

void main() {
  testWidgets('app without a saved session opens phone login', (tester) async {
    await tester.pumpWidget(
      SmartReminderApp(
        config: const AppConfig(
          apiBaseUrl: 'http://127.0.0.1:1',
        ),
        notificationScheduler: NoopScheduler(),
        tokenStore: EmptyTokenStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智能提醒'), findsOneWidget);
    expect(find.text('登录'), findsWidgets);
    expect(find.text('注册'), findsOneWidget);
    expect(find.byKey(const Key('phone-field')), findsOneWidget);
  });
}

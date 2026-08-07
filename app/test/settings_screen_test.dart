import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/settings/settings_screen.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';

void main() {
  testWidgets('updates theme and invokes password and logout account actions',
      (tester) async {
    var theme = ThemeMode.system;
    var passwordCalls = 0;
    var logoutCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => SettingsScreen(
            user: const AuthUser(
              id: 'user-1',
              phoneMasked: '138****8000',
              phoneVerified: false,
            ),
            themeMode: theme,
            onThemeModeChanged: (value) => setState(() => theme = value),
            onChangePassword: (_, __, ___) async => passwordCalls += 1,
            onLogout: () async => logoutCalls += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(theme, ThemeMode.dark);

    await tester.tap(find.text('修改密码'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('current-password-field')),
      'Current-password-2026',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'New-password-2026',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-confirm-field')),
      'New-password-2026',
    );
    await tester.tap(find.text('保存新密码'));
    await tester.pumpAndSettle();
    expect(passwordCalls, 1);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认退出'));
    await tester.pumpAndSettle();
    expect(logoutCalls, 1);
  });
}

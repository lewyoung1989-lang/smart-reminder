import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';
import 'package:smart_reminder_app/features/profile/presentation/profile_screen.dart';

void main() {
  testWidgets('profile shows masked phone and unverified state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          user: const AuthUser(
            id: '1',
            phoneMasked: '138****8000',
            phoneVerified: false,
          ),
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
        ),
      ),
    );

    expect(find.text('138****8000'), findsOneWidget);
    expect(find.text('手机号未验证'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
  });

  testWidgets('profile confirms logout command', (tester) async {
    var logoutCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          user: const AuthUser(
            id: '1',
            phoneMasked: '138****8000',
            phoneVerified: false,
          ),
          onChangePassword: (_, __, ___) async {},
          onLogout: () async => logoutCalls += 1,
        ),
      ),
    );

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认退出'));
    await tester.pumpAndSettle();

    expect(logoutCalls, 1);
  });
}

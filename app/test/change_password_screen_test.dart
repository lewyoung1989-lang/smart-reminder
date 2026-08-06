import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/auth/data/auth_api.dart';
import 'package:smart_reminder_app/features/profile/presentation/change_password_screen.dart';

void main() {
  testWidgets('change password maps an incorrect current password',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangePasswordScreen(
          onSubmit: (_, __, ___) async => throw const AuthApiException(
            400,
            code: 'invalid_current_password',
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('current-password-field')),
      'Wrong-pass-2026',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'New-pass-2026',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-confirm-field')),
      'New-pass-2026',
    );

    await tester.tap(find.text('保存新密码'));
    await tester.pumpAndSettle();

    expect(find.text('当前密码错误'), findsOneWidget);
  });
}

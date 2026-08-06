import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/auth/data/auth_api.dart';
import 'package:smart_reminder_app/features/auth/presentation/auth_screen.dart';

Widget buildScreen({
  Future<void> Function(String phone, String password)? login,
  Future<void> Function(
    String phone,
    String password,
    String passwordConfirm,
  )? register,
}) =>
    MaterialApp(
      home: AuthScreen(
        onLogin: login ?? (_, __) async {},
        onRegister: register ?? (_, __, ___) async {},
      ),
    );

void main() {
  testWidgets('registration maps duplicate phone and preserves input',
      (tester) async {
    await tester.pumpWidget(
      buildScreen(
        register: (_, __, ___) async => throw const AuthApiException(
          409,
          code: 'phone_already_registered',
        ),
      ),
    );
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('phone-field')),
      '13800138000',
    );
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'Good-pass-2026',
    );
    await tester.enterText(
      find.byKey(const Key('password-confirm-field')),
      'Good-pass-2026',
    );

    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text('该手机号已注册，请直接登录'), findsOneWidget);
    final phone = tester.widget<TextFormField>(
      find.byKey(const Key('phone-field')),
    );
    expect(phone.controller?.text, '13800138000');
  });

  testWidgets('local validation rejects malformed phone before login',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildScreen(login: (_, __) async => calls += 1),
    );
    await tester.enterText(find.byKey(const Key('phone-field')), '123');
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'Good-pass-2026',
    );

    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();

    expect(find.text('请输入正确的 11 位手机号'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('backend field error is shown on the matching input',
      (tester) async {
    await tester.pumpWidget(
      buildScreen(
        login: (_, __) async => throw const AuthApiException(
          400,
          code: 'invalid_phone',
          field: 'phone',
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('phone-field')),
      '13800138000',
    );
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'Good-pass-2026',
    );

    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text('请输入正确的 11 位手机号'), findsOneWidget);
    expect(find.byKey(const Key('auth-error')), findsNothing);
  });

  testWidgets('rate limit disables submission for retry-after duration',
      (tester) async {
    await tester.pumpWidget(
      buildScreen(
        login: (_, __) async => throw const AuthApiException(
          429,
          code: 'rate_limited',
          retryAfter: 2,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('phone-field')),
      '13800138000',
    );
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'Good-pass-2026',
    );

    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();
    await tester.pump();

    expect(find.text('操作过于频繁，请 2 秒后重试'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auth-submit')))
          .onPressed,
      isNull,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('操作过于频繁，请 1 秒后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auth-submit')))
          .onPressed,
      isNotNull,
    );
  });
}

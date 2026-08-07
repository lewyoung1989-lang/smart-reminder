import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/config/app_config.dart';
import 'package:smart_reminder_app/features/auth/application/auth_controller.dart';
import 'package:smart_reminder_app/features/auth/data/auth_api.dart';
import 'package:smart_reminder_app/features/auth/data/token_store.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/main.dart';
import 'package:smart_reminder_app/platform/permissions/camera_permission_gateway.dart';
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

  testWidgets('session expiry clears protected settings before showing login',
      (tester) async {
    final controller = AuthController(
      tokenStore: EmptyTokenStore(),
      gateway: _AuthenticatedGateway(),
    );
    addTearDown(controller.dispose);
    await controller.login(phone: '13800138000', password: 'password123');

    await tester.pumpWidget(
      SmartReminderApp(
        config: const AppConfig(apiBaseUrl: 'http://127.0.0.1:1'),
        notificationScheduler: NoopScheduler(),
        tokenStore: EmptyTokenStore(),
        authController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('打开设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);

    controller.expireSession();
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(find.byKey(const Key('phone-field')), findsOneWidget);
  });

  testWidgets(
      'permanent camera denial exposes system settings from the cabinet',
      (tester) async {
    final controller = AuthController(
      tokenStore: EmptyTokenStore(),
      gateway: _AuthenticatedGateway(),
    );
    addTearDown(controller.dispose);
    await controller.login(phone: '13800138000', password: 'password123');
    final cameraPermissions = _CameraPermissions(
      CameraPermissionState.permanentlyDenied,
    );

    await tester.pumpWidget(
      SmartReminderApp(
        config: const AppConfig(apiBaseUrl: 'http://127.0.0.1:1'),
        notificationScheduler: NoopScheduler(),
        tokenStore: EmptyTokenStore(),
        authController: controller,
        cameraPermissionGateway: cameraPermissions,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('药箱'));
    await tester.pumpAndSettle();

    expect(find.text('需要相机权限才能拍照录入'), findsOneWidget);
    await tester.tap(find.text('打开设置'));
    expect(cameraPermissions.openSettingsCalls, 1);
  });
}

class _CameraPermissions implements CameraPermissionGateway {
  _CameraPermissions(this.state);

  CameraPermissionState state;
  var openSettingsCalls = 0;

  @override
  Future<CameraPermissionState> current() async => state;

  @override
  Future<bool> openSystemSettings() async {
    openSettingsCalls += 1;
    return true;
  }

  @override
  Future<CameraPermissionState> request() async => state;
}

class _AuthenticatedGateway implements AuthGateway {
  static const _session = AuthSession(
    user: AuthUser(
      id: 'user-1',
      phoneMasked: '138****8000',
      phoneVerified: true,
    ),
    tokens: AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessExpiresIn: 3600,
    ),
  );

  @override
  Future<AuthSession> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirm,
  }) async =>
      _session;

  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
  }) async =>
      _session;

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<AuthUser> me() async => _session.user;

  @override
  Future<AuthSession> register({
    required String phone,
    required String password,
    required String passwordConfirm,
  }) async =>
      _session;
}

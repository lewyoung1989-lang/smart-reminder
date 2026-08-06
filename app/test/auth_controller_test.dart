import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/auth/application/auth_controller.dart';
import 'package:smart_reminder_app/features/auth/data/auth_api.dart';
import 'package:smart_reminder_app/features/auth/data/token_store.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore(this.tokens, {this.readError});

  AuthTokens? tokens;
  Object? readError;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async {
    if (readError != null) throw readError!;
    return tokens;
  }

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

class FakeAuthGateway implements AuthGateway {
  AuthUser user = const AuthUser(
    id: '1',
    phoneMasked: '138****8000',
    phoneVerified: false,
  );
  AuthSession? session;
  Object? meError;
  Object? logoutError;

  @override
  Future<AuthSession> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirm,
  }) async =>
      session!;

  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
  }) async =>
      session!;

  @override
  Future<void> logout(String refreshToken) async {
    if (logoutError != null) throw logoutError!;
  }

  @override
  Future<AuthUser> me() async {
    if (meError != null) throw meError!;
    return user;
  }

  @override
  Future<AuthSession> register({
    required String phone,
    required String password,
    required String passwordConfirm,
  }) async =>
      session!;
}

const tokens = AuthTokens(
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresIn: 900,
);

void main() {
  test('restore without tokens becomes unauthenticated', () async {
    final controller = AuthController(
      tokenStore: MemoryTokenStore(null),
      gateway: FakeAuthGateway(),
    );

    await controller.restore();

    expect(controller.status, AuthStatus.unauthenticated);
  });

  test('restore with valid tokens loads the current user', () async {
    final controller = AuthController(
      tokenStore: MemoryTokenStore(tokens),
      gateway: FakeAuthGateway(),
    );

    await controller.restore();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user?.phoneMasked, '138****8000');
  });

  test('network failure during restore preserves tokens and allows retry',
      () async {
    final store = MemoryTokenStore(tokens);
    final gateway = FakeAuthGateway()
      ..meError = http.ClientException('offline');
    final controller = AuthController(tokenStore: store, gateway: gateway);

    await controller.restore();

    expect(controller.status, AuthStatus.connectionError);
    expect(await store.read(), tokens);
    gateway.meError = null;
    await controller.restore();
    expect(controller.status, AuthStatus.authenticated);
  });

  test('unexpected restore failure leaves retryable connection error state',
      () async {
    final store = MemoryTokenStore(tokens);
    final gateway = FakeAuthGateway()..meError = const FormatException('bad');
    final controller = AuthController(tokenStore: store, gateway: gateway);

    await controller.restore();

    expect(controller.status, AuthStatus.connectionError);
    expect(await store.read(), tokens);
  });

  test('secure storage read failure leaves retryable connection error state',
      () async {
    final store = MemoryTokenStore(
      tokens,
      readError: StateError('keychain unavailable'),
    );
    final controller = AuthController(
      tokenStore: store,
      gateway: FakeAuthGateway(),
    );

    await expectLater(controller.restore(), completes);

    expect(controller.status, AuthStatus.connectionError);
  });

  test('successful login stores tokens and user', () async {
    final store = MemoryTokenStore(null);
    final gateway = FakeAuthGateway()
      ..session = AuthSession(user: FakeAuthGateway().user, tokens: tokens);
    final controller = AuthController(tokenStore: store, gateway: gateway);

    await controller.login(phone: '13800138000', password: 'password');

    expect(controller.status, AuthStatus.authenticated);
    expect(await store.read(), tokens);
  });

  test('logout clears local state when the server is unavailable', () async {
    final store = MemoryTokenStore(tokens);
    final gateway = FakeAuthGateway()
      ..logoutError = http.ClientException('offline');
    final controller = AuthController(tokenStore: store, gateway: gateway);
    await controller.restore();

    await expectLater(
        controller.logout(), throwsA(isA<http.ClientException>()));

    expect(await store.read(), isNull);
    expect(controller.status, AuthStatus.unauthenticated);
  });
}

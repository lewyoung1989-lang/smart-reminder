import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/core/network/authenticated_client.dart';
import 'package:smart_reminder_app/features/auth/data/auth_api.dart';
import 'package:smart_reminder_app/features/auth/data/token_store.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore(this.tokens);

  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

class AuthRecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final authorization = request.headers['Authorization'];
    final status = authorization == 'Bearer new-access' ? 200 : 401;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

const oldTokens = AuthTokens(
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
  accessExpiresIn: 900,
);
const newTokens = AuthTokens(
  accessToken: 'new-access',
  refreshToken: 'new-refresh',
  accessExpiresIn: 900,
);

void main() {
  test('concurrent 401 responses perform one refresh and retry once', () async {
    final inner = AuthRecordingClient();
    final store = MemoryTokenStore(oldTokens);
    var refreshCalls = 0;
    final client = AuthenticatedClient(
      apiBaseUri: Uri.parse('https://api.invalid'),
      inner: inner,
      tokenStore: store,
      refreshTokens: (refreshToken) async {
        refreshCalls += 1;
        expect(refreshToken, 'old-refresh');
        await Future<void>.delayed(Duration.zero);
        return newTokens;
      },
    );

    final responses = await Future.wait([
      client.get(Uri.parse('https://api.invalid/one')),
      client.post(Uri.parse('https://api.invalid/two'), body: 'payload'),
    ]);

    expect(refreshCalls, 1);
    expect(responses.map((response) => response.statusCode), everyElement(200));
    expect(await store.read(), newTokens);
    expect(inner.requests, hasLength(4));
  });

  test('invalid refresh token clears tokens and reports session expiry',
      () async {
    final store = MemoryTokenStore(oldTokens);
    var expiryNotifications = 0;
    final client = AuthenticatedClient(
      apiBaseUri: Uri.parse('https://api.invalid'),
      inner: AuthRecordingClient(),
      tokenStore: store,
      refreshTokens: (_) async => throw const AuthApiException(
        401,
        code: 'invalid_refresh_token',
      ),
      onSessionExpired: () => expiryNotifications += 1,
    );

    await expectLater(
      client.get(Uri.parse('https://api.invalid/protected')),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(await store.read(), isNull);
    expect(expiryNotifications, 1);
  });

  test('temporary refresh failure preserves tokens and can be retried',
      () async {
    final store = MemoryTokenStore(oldTokens);
    var expiryNotifications = 0;
    final temporaryFailure = http.ClientException('offline');
    final client = AuthenticatedClient(
      apiBaseUri: Uri.parse('https://api.invalid'),
      inner: AuthRecordingClient(),
      tokenStore: store,
      refreshTokens: (_) async => throw temporaryFailure,
      onSessionExpired: () => expiryNotifications += 1,
    );

    await expectLater(
      client.get(Uri.parse('https://api.invalid/protected')),
      throwsA(same(temporaryFailure)),
    );
    expect(await store.read(), oldTokens);
    expect(expiryNotifications, 0);
  });

  test('external signed upload never receives the API token', () async {
    final inner = AuthRecordingClient();
    final client = AuthenticatedClient(
      apiBaseUri: Uri.parse('https://api.invalid'),
      inner: inner,
      tokenStore: MemoryTokenStore(oldTokens),
      refreshTokens: (_) async => newTokens,
    );

    await client.put(Uri.parse('https://files.invalid/upload'), body: [1, 2]);

    expect(inner.requests.single.headers['Authorization'], isNull);
  });
}

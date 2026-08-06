import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/auth/data/secure_token_store.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';

class FakeSecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('secure token store writes reads and clears a token pair', () async {
    final secureValues = FakeSecureKeyValueStore();
    final store = SecureTokenStore(secureValues);
    const tokens = AuthTokens(
      accessToken: 'access-value',
      refreshToken: 'refresh-value',
      accessExpiresIn: 900,
    );

    await store.write(tokens);
    expect(await store.read(), tokens);
    expect(secureValues.values.keys, {'auth_token_bundle'});

    await store.clear();
    expect(await store.read(), isNull);
    expect(secureValues.values, isEmpty);
  });

  test('partial secure state is treated as signed out and removed', () async {
    final secureValues = FakeSecureKeyValueStore()
      ..values['auth_access_token'] = 'orphan';
    final store = SecureTokenStore(secureValues);

    expect(await store.read(), isNull);
    expect(secureValues.values, isEmpty);
  });

  test('complete legacy token state is migrated to one bundle', () async {
    final secureValues = FakeSecureKeyValueStore()
      ..values['auth_access_token'] = 'legacy-access'
      ..values['auth_refresh_token'] = 'legacy-refresh'
      ..values['auth_access_expires_in'] = '900';
    final store = SecureTokenStore(secureValues);

    expect(
      await store.read(),
      const AuthTokens(
        accessToken: 'legacy-access',
        refreshToken: 'legacy-refresh',
        accessExpiresIn: 900,
      ),
    );
    expect(secureValues.values.keys, {'auth_token_bundle'});
  });

  test('malformed token bundle is treated as signed out and removed', () async {
    final secureValues = FakeSecureKeyValueStore()
      ..values['auth_token_bundle'] = '{broken-json';
    final store = SecureTokenStore(secureValues);

    expect(await store.read(), isNull);
    expect(secureValues.values, isEmpty);
  });
}

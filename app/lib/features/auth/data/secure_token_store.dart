import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_models.dart';
import 'token_store.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore(this._storage);

  static const _bundleKey = 'auth_token_bundle';
  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _expiresKey = 'auth_access_expires_in';

  final SecureKeyValueStore _storage;

  @override
  Future<AuthTokens?> read() async {
    final bundle = await _storage.read(_bundleKey);
    if (bundle != null) {
      try {
        final json = jsonDecode(bundle) as Map<String, dynamic>;
        return AuthTokens.fromJson(json);
      } on Object {
        await clear();
        return null;
      }
    }

    final values = await Future.wait([
      _storage.read(_accessKey),
      _storage.read(_refreshKey),
      _storage.read(_expiresKey),
    ]);
    final expiresIn = int.tryParse(values[2] ?? '');
    if (values[0] == null || values[1] == null || expiresIn == null) {
      if (values.any((value) => value != null)) {
        await clear();
      }
      return null;
    }
    final tokens = AuthTokens(
      accessToken: values[0]!,
      refreshToken: values[1]!,
      accessExpiresIn: expiresIn,
    );
    await write(tokens);
    return tokens;
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    await _storage.write(
      _bundleKey,
      jsonEncode({
        'access_token': tokens.accessToken,
        'refresh_token': tokens.refreshToken,
        'access_expires_in': tokens.accessExpiresIn,
      }),
    );
    await _clearLegacyKeys();
  }

  @override
  Future<void> clear() => Future.wait([
        _storage.delete(_bundleKey),
        _storage.delete(_accessKey),
        _storage.delete(_refreshKey),
        _storage.delete(_expiresKey),
      ]);

  Future<void> _clearLegacyKeys() => Future.wait([
        _storage.delete(_accessKey),
        _storage.delete(_refreshKey),
        _storage.delete(_expiresKey),
      ]);
}

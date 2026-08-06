import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/auth_models.dart';

abstract interface class AuthGateway {
  Future<AuthSession> register({
    required String phone,
    required String password,
    required String passwordConfirm,
  });
  Future<AuthSession> login({
    required String phone,
    required String password,
  });
  Future<AuthUser> me();
  Future<void> logout(String refreshToken);
  Future<AuthSession> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirm,
  });
}

class AuthApi implements AuthGateway {
  AuthApi({required String baseUrl, http.Client? client})
      : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  @override
  Future<AuthSession> register({
    required String phone,
    required String password,
    required String passwordConfirm,
  }) async {
    final response = await _post('/api/v1/auth/register', {
      'phone': phone,
      'password': password,
      'password_confirm': passwordConfirm,
    });
    _requireStatus(response, 201);
    return AuthSession.fromJson(_jsonObject(response));
  }

  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
  }) async {
    final response = await _post('/api/v1/auth/login', {
      'phone': phone,
      'password': password,
    });
    _requireStatus(response, 200);
    return AuthSession.fromJson(_jsonObject(response));
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final response = await _post('/api/v1/auth/refresh', {
      'refresh_token': refreshToken,
    });
    _requireStatus(response, 200);
    return AuthTokens.fromJson(_jsonObject(response));
  }

  @override
  Future<AuthUser> me() async {
    final response = await _client.get(
      _baseUri.resolve('/api/v1/auth/me'),
      headers: const {'Accept': 'application/json'},
    );
    _requireStatus(response, 200);
    return AuthUser.fromJson(_jsonObject(response));
  }

  @override
  Future<void> logout(String refreshToken) async {
    final response = await _post('/api/v1/auth/logout', {
      'refresh_token': refreshToken,
    });
    _requireStatus(response, 204);
  }

  @override
  Future<AuthSession> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirm,
  }) async {
    final response = await _post('/api/v1/auth/password/change', {
      'current_password': currentPassword,
      'new_password': newPassword,
      'new_password_confirm': newPasswordConfirm,
    });
    _requireStatus(response, 200);
    return AuthSession.fromJson(_jsonObject(response));
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) =>
      _client.post(
        _baseUri.resolve(path),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

  static Map<String, dynamic> _jsonObject(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  static void _requireStatus(http.Response response, int expected) {
    if (response.statusCode == expected) {
      return;
    }
    String? code;
    String? field;
    int? retryAfter;
    try {
      final json = _jsonObject(response);
      code = json['code'] as String?;
      field = json['field'] as String?;
      retryAfter = json['retry_after'] as int?;
    } on FormatException {
      // A non-JSON server error still maps to a bounded domain exception.
    }
    throw AuthApiException(
      response.statusCode,
      code: code,
      field: field,
      retryAfter: retryAfter,
    );
  }

  void close() => _client.close();
}

class AuthApiException implements Exception {
  const AuthApiException(
    this.statusCode, {
    this.code,
    this.field,
    this.retryAfter,
  });

  final int statusCode;
  final String? code;
  final String? field;
  final int? retryAfter;
}

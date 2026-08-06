import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/auth/data/auth_api.dart';

class QueueClient extends http.BaseClient {
  QueueClient(this.responses);

  final List<http.Response> responses;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

http.Response jsonResponse(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('register parses user and token payload', () async {
    final client = QueueClient([
      jsonResponse(201, {
        'user': {
          'id': '12',
          'phone_masked': '138****8000',
          'phone_verified': false,
        },
        'access_token': 'access',
        'refresh_token': 'refresh',
        'access_expires_in': 900,
      }),
    ]);
    final api = AuthApi(baseUrl: 'https://api.invalid', client: client);

    final session = await api.register(
      phone: '13800138000',
      password: 'Good-pass-2026',
      passwordConfirm: 'Good-pass-2026',
    );

    expect(session.user.phoneMasked, '138****8000');
    expect(session.tokens.refreshToken, 'refresh');
    expect(client.requests.single.url.path, '/api/v1/auth/register');
  });

  test('refresh maps stable authentication errors', () async {
    final client = QueueClient([
      jsonResponse(401, {'code': 'invalid_refresh_token'}),
    ]);
    final api = AuthApi(baseUrl: 'https://api.invalid', client: client);

    await expectLater(
      api.refresh('expired'),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having(
              (error) => error.code,
              'code',
              'invalid_refresh_token',
            ),
      ),
    );
  });
}

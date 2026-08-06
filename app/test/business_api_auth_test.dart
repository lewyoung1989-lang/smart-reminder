import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/reminders/data/reminder_api.dart';

class RecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({
        'next': null,
        'previous': null,
        'results': <Object>[],
      }))),
      200,
    );
  }
}

void main() {
  test('business api delegates authentication to the shared client', () async {
    final client = RecordingClient();
    final api = ReminderApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    await api.list();

    expect(client.requests.single.headers['Authorization'], isNull);
  });
}

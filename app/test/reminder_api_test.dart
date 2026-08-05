import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/reminders/data/reminder_api.dart';
import 'package:smart_reminder_app/features/reminders/domain/reminder.dart';

class RecordingClient extends http.BaseClient {
  RecordingClient(this.responses);

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
  Map<String, dynamic> reminderJson({
    String severity = 'notification',
    String status = 'pending',
  }) =>
      {
        'id': 'reminder-1',
        'title': '喝水',
        'timezone': 'Asia/Shanghai',
        'scheduled_at': '2026-08-05T12:30:00+08:00',
        'severity': severity,
        'status': status,
        'cancelled_at': null,
      };

  test('rejects unknown reminder severity and status values', () {
    expect(
      () => Reminder.fromJson(reminderJson(severity: 'email')),
      throwsFormatException,
    );
    expect(
      () => Reminder.fromJson(reminderJson(status: 'snoozed')),
      throwsFormatException,
    );
  });

  test('lists a status page and parses reminder lifecycle fields', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'next':
            'https://api.invalid/api/v1/reminders?cursor=next&status=pending',
        'previous': null,
        'results': [
          {
            'id': 'reminder-1',
            'title': '喝水',
            'timezone': 'Asia/Shanghai',
            'scheduled_at': '2026-08-05T12:30:00+08:00',
            'severity': 'notification',
            'status': 'pending',
            'cancelled_at': null,
          },
        ],
      }),
    ]);
    final api = ReminderApi(
      baseUrl: 'https://api.invalid',
      accessToken: 'token',
      client: client,
    );

    final page = await api.list(status: ReminderStatus.pending);

    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.url.path, '/api/v1/reminders');
    expect(client.requests.single.url.queryParameters['status'], 'pending');
    expect(client.requests.single.headers['Authorization'], 'Bearer token');
    expect(page.reminders.single.title, '喝水');
    expect(page.reminders.single.status, ReminderStatus.pending);
    expect(page.reminders.single.cancelledAt, isNull);
    expect(page.reminders.single.scheduledAt.hour, 12);
    expect(page.nextPage?.queryParameters['cursor'], 'next');
  });

  test('follows only same-origin cursor URLs', () async {
    final client = RecordingClient([
      jsonResponse(200, {'next': null, 'previous': null, 'results': []}),
    ]);
    final api = ReminderApi(
      baseUrl: 'https://api.invalid',
      accessToken: 'token',
      client: client,
    );

    await expectLater(
      api.list(
        status: ReminderStatus.pending,
        pageUrl: Uri.parse('https://other.invalid/reminders?cursor=stolen'),
      ),
      throwsA(isA<ReminderApiException>()),
    );
    expect(client.requests, isEmpty);

    await api.list(
      status: ReminderStatus.pending,
      pageUrl: Uri.parse(
        'https://api.invalid/api/v1/reminders?cursor=next&status=pending',
      ),
    );
    expect(client.requests.single.url.queryParameters['cursor'], 'next');
  });

  test('cancels a reminder and reports a conflict without retrying', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'id': 'reminder-1',
        'title': '喝水',
        'timezone': 'Asia/Shanghai',
        'scheduled_at': '2026-08-05T12:30:00+08:00',
        'severity': 'notification',
        'status': 'cancelled',
        'cancelled_at': '2026-08-05T12:00:00+08:00',
      }),
      jsonResponse(409, {
        'code': 'reminder_expired',
        'detail': '提醒时间已过，不能取消',
      }),
    ]);
    final api = ReminderApi(
      baseUrl: 'https://api.invalid',
      accessToken: 'token',
      client: client,
    );

    final cancelled = await api.cancel('reminder-1');

    expect(client.requests.first.method, 'POST');
    expect(
        client.requests.first.url.path, '/api/v1/reminders/reminder-1/cancel');
    expect(cancelled.status, ReminderStatus.cancelled);
    expect(cancelled.cancelledAt, isNotNull);

    try {
      await api.cancel('reminder-2');
      fail('expected reminder conflict');
    } on ReminderApiException catch (error) {
      expect(error.statusCode, 409);
      expect(error.code, 'reminder_expired');
    }
    expect(client.requests, hasLength(2));
  });
}

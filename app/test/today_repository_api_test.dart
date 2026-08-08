import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/today/data/today_repository.dart';
import 'package:smart_reminder_app/features/today/domain/today_models.dart';

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
  test('loads action center decisions and upcoming timeline from backend', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'need_decision': {
          'next': null,
          'results': [
            {
              'id': 'expiry-alert-1',
              'title': '滴眼液已到期，请确认是否已处理',
              'kind': 'medicine_expiry',
              'status': 'expired',
              'occurred_at': '2026-08-08',
            },
            {
              'id': 'medication-1',
              'title': '服用布洛芬（1粒）',
              'kind': 'medication',
              'status': 'due',
              'occurred_at': '2026-08-08T08:00:00+08:00',
            },
          ],
        },
        'upcoming': {
          'next': null,
          'results': [
            {
              'id': 'departure-1',
              'title': '去虹桥火车站',
              'kind': 'workflow',
              'status': 'scheduled',
              'occurred_at': '2026-08-08T17:10:00+08:00',
            },
          ],
        },
      }),
    ]);
    final repository = ApiTodayRepository(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final snapshot = await repository.load();

    expect(client.requests.single.method, 'GET');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/action-center/today',
    );
    expect(client.requests.single.headers['Authorization'], isNull);
    expect(snapshot.decisions, hasLength(2));
    expect(snapshot.decisions.first.id, 'expiry-alert-1');
    expect(snapshot.decisions.first.kind, AttentionKind.confirmation);
    expect(snapshot.decisions.first.actionLabel, '处理');
    expect(snapshot.decisions.last.title, '服用布洛芬（1粒）');
    expect(snapshot.decisions.last.dueAt, DateTime.parse('2026-08-08T08:00:00+08:00'));
    expect(snapshot.timeline.single.id, 'departure-1');
    expect(snapshot.timeline.single.status, TimelineStatus.upcoming);
    expect(snapshot.timeline.single.scheduledAt, DateTime.parse('2026-08-08T17:10:00+08:00'));
  });

  test('throws a stable exception for action center server errors', () async {
    final repository = ApiTodayRepository(
      baseUrl: 'https://api.invalid',
      client: RecordingClient([
        jsonResponse(503, {'detail': 'unavailable'})
      ]),
    );

    await expectLater(
      repository.load(),
      throwsA(
        isA<TodayApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });
}

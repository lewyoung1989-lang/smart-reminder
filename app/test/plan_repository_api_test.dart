import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/plans/data/api_plan_repository.dart';
import 'package:smart_reminder_app/features/plans/domain/plan_models.dart';

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
  test('loads periodic plans from backend', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'is_offline': false,
        'results': [
          {
            'id': 'plan-1',
            'title': '用药提醒',
            'subtitle': '布洛芬 · 1片',
            'next_run_at': '2026-08-11T12:00:00+00:00',
            'status': 'active',
            'kind': 'medication',
          },
        ],
      }),
    ]);
    final repository = ApiPlanRepository(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final collection = await repository.load();

    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.url.path, '/api/v1/plans');
    expect(collection.isOffline, isFalse);
    expect(collection.items.single.id, 'plan-1');
    expect(collection.items.single.subtitle, '布洛芬 · 1片');
    expect(collection.items.single.status, PlanStatus.active);
    expect(collection.items.single.kind, PlanKind.medication);
    expect(
      collection.items.single.nextRunAt,
      DateTime.parse('2026-08-11T12:00:00+00:00').toLocal(),
    );
  });

  test('loads periodic plan detail from backend', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'summary': {
          'id': 'plan-1',
          'title': '用药提醒',
          'subtitle': '布洛芬 · 1片',
          'next_run_at': '2026-08-11T12:00:00+00:00',
          'status': 'active',
          'kind': 'medication',
        },
        'arrival_label': null,
        'destination': null,
        'queried_sources': [],
        'reminder_label': '每天 20:00 通知提醒',
        'executions': [],
        'is_degraded': false,
        'degradation_message': null,
      }),
    ]);
    final repository = ApiPlanRepository(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final detail = await repository.getById('plan-1');

    expect(client.requests.single.url.path, '/api/v1/plans/plan-1');
    expect(detail.summary.title, '用药提醒');
    expect(detail.reminderLabel, '每天 20:00 通知提醒');
    expect(detail.executions, isEmpty);
  });

  test('throws a stable exception for server errors', () async {
    final repository = ApiPlanRepository(
      baseUrl: 'https://api.invalid',
      client: RecordingClient([
        jsonResponse(500, {'detail': 'boom'})
      ]),
    );

    await expectLater(
      repository.load(),
      throwsA(isA<PlanApiException>()),
    );
  });
}

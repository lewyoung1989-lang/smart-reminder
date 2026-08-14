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
        'executions': [
          {
            'started_at': '2026-08-11T12:00:00+00:00',
            'status': 'pending',
            'message': '等待执行',
          },
        ],
        'is_degraded': false,
        'degradation_message': null,
        'source_text': '每天晚上八点吃布洛芬一片',
        'notification_schedule': {
          'scheduled_at': '2026-08-11T12:00:00+00:00',
          'repeat': 'daily',
          'title': '用药提醒',
          'timezone': 'Asia/Shanghai',
        },
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
    expect(detail.executions.single.status, PlanExecutionStatus.pending);
    expect(detail.sourceText, '每天晚上八点吃布洛芬一片');
    expect(detail.notificationSchedule?.repeat, PlanRepeat.daily);
    expect(detail.notificationSchedule?.timezone, 'Asia/Shanghai');
  });

  test('loads all daily notification times from plan detail', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'summary': {
          'id': 'plan-3-times',
          'title': '用药提醒',
          'subtitle': '拜新同 · 1片',
          'next_run_at': '2026-08-11T12:00:00+00:00',
          'status': 'active',
          'kind': 'medication',
        },
        'queried_sources': <String>[],
        'reminder_label': '每天 08:00、13:00、20:00 通知提醒',
        'executions': <Object>[],
        'notification_schedule': {
          'scheduled_at': '2026-08-11T12:00:00+00:00',
          'scheduled_times': [
            '2026-08-12T00:00:00+00:00',
            '2026-08-12T05:00:00+00:00',
            '2026-08-11T12:00:00+00:00',
          ],
          'repeat': 'daily',
          'title': '用药提醒',
          'timezone': 'Asia/Shanghai',
        },
      }),
    ]);
    final repository = ApiPlanRepository(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final detail = await repository.getById('plan-3-times');

    expect(detail.notificationSchedule?.scheduledTimes, hasLength(3));
    expect(
      detail.notificationSchedule?.scheduledTimes.map((value) => value.hour),
      [0, 5, 12],
    );
  });

  test('pauses resumes and deletes a periodic plan', () async {
    Map<String, Object?> detail(String status) => {
          'summary': {
            'id': 'plan-1',
            'title': '用药提醒',
            'subtitle': '布洛芬 · 1片',
            'next_run_at': '2026-08-11T12:00:00+00:00',
            'status': status,
            'kind': 'medication',
          },
          'queried_sources': <String>[],
          'reminder_label': '每天 20:00 通知提醒',
          'executions': <Object>[],
        };
    final client = RecordingClient([
      jsonResponse(200, detail('paused')),
      jsonResponse(200, detail('active')),
      http.Response('', 204),
    ]);
    final repository = ApiPlanRepository(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    expect(
        (await repository.pause('plan-1')).summary.status, PlanStatus.paused);
    expect(
        (await repository.resume('plan-1')).summary.status, PlanStatus.active);
    await repository.delete('plan-1');

    expect(client.requests.map((request) => request.method),
        ['POST', 'POST', 'DELETE']);
    expect(client.requests[0].url.path, '/api/v1/plans/plan-1/pause');
    expect(client.requests[1].url.path, '/api/v1/plans/plan-1/resume');
    expect(client.requests[2].url.path, '/api/v1/plans/plan-1');
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

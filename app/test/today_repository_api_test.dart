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
  test('loads action center decisions and upcoming timeline from backend',
      () async {
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
              'action_target': {
                'resource': 'inventory_batch',
                'id': 'batch-1',
              },
            },
            {
              'id': 'medication-1',
              'title': '服用布洛芬（1粒）',
              'kind': 'medication',
              'status': 'due',
              'occurred_at': '2026-08-08T08:00:00+08:00',
              'action_target': {
                'resource': 'medication_occurrence',
                'id': 'medication-1',
              },
            },
            {
              'id': 'low-stock-1',
              'title': '拜新同余量不足，还能用约2天（剩余2片）',
              'kind': 'medicine_low_stock',
              'status': 'low_stock',
              'occurred_at': '2026-08-08T09:00:00+08:00',
              'action_target': {
                'resource': 'low_stock_alert',
                'id': 'low-stock-1',
              },
            },
            {
              'id': 'reminder-due-1',
              'title': '给妈妈打电话',
              'kind': 'reminder',
              'status': 'due',
              'occurred_at': '2026-08-08T08:30:00+08:00',
              'action_target': {
                'resource': 'reminder',
                'id': 'reminder-due-1',
                'action': 'complete',
              },
              'secondary_action_target': {
                'resource': 'reminder',
                'id': 'reminder-due-1',
                'action': 'snooze',
              },
            },
          ],
        },
        'upcoming': {
          'next': null,
          'results': [
            {
              'id': 'departure-1',
              'title': '去虹桥火车站',
              'subtitle': '虹桥火车站',
              'kind': 'workflow',
              'status': 'scheduled',
              'occurred_at': '2026-08-08T09:10:00+00:00',
              'action_target': {
                'resource': 'workflow',
                'id': 'departure-1',
              },
            },
            {
              'id': 'reminder-1',
              'title': '晚上测血压',
              'kind': 'reminder',
              'status': 'scheduled',
              'occurred_at': '2026-08-08T20:00:00+08:00',
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
    expect(snapshot.decisions, hasLength(4));
    expect(snapshot.decisions.first.id, 'expiry-alert-1');
    expect(snapshot.decisions.first.kind, AttentionKind.confirmation);
    expect(snapshot.decisions.first.actionLabel, '处理');
    expect(snapshot.decisions.first.actionTarget?.resource, 'inventory_batch');
    expect(snapshot.decisions.first.actionTarget?.id, 'batch-1');
    expect(snapshot.decisions[1].title, '服用布洛芬（1粒）');
    expect(
      snapshot.decisions[1].actionTarget?.resource,
      'medication_occurrence',
    );
    expect(snapshot.decisions[1].dueAt,
        DateTime.parse('2026-08-08T08:00:00+08:00').toLocal());
    expect(snapshot.decisions[2].title, '拜新同余量不足，还能用约2天（剩余2片）');
    expect(snapshot.decisions[2].reason, '药箱余量不足，需要补库存');
    expect(snapshot.decisions[2].actionLabel, '处理');
    expect(snapshot.decisions[2].actionTarget?.resource, 'low_stock_alert');
    expect(snapshot.decisions.last.title, '给妈妈打电话');
    expect(snapshot.decisions.last.reason, '提醒时间到了');
    expect(snapshot.decisions.last.actionLabel, '完成');
    expect(snapshot.decisions.last.actionTarget?.resource, 'reminder');
    expect(snapshot.decisions.last.actionTarget?.action, 'complete');
    expect(snapshot.decisions.last.secondaryActionLabel, '稍后');
    expect(snapshot.decisions.last.secondaryActionTarget?.action, 'snooze');
    expect(snapshot.timeline.first.id, 'departure-1');
    expect(snapshot.timeline.first.subtitle, '虹桥火车站');
    expect(snapshot.timeline.first.status, TimelineStatus.upcoming);
    expect(snapshot.timeline.first.actionTarget?.resource, 'workflow');
    expect(snapshot.timeline.first.actionTarget?.id, 'departure-1');
    expect(snapshot.timeline.first.scheduledAt,
        DateTime.parse('2026-08-08T09:10:00+00:00').toLocal());
    expect(snapshot.timeline.last.id, 'reminder-1');
    expect(snapshot.timeline.last.subtitle, '普通提醒');
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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/today/data/action_center_api.dart';

class RecordingClient extends http.BaseClient {
  RecordingClient(this.responses);

  final List<http.Response> responses;
  final requests = <http.BaseRequest>[];
  final requestBodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request) {
      requestBodies.add(request.body);
    }
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
  test('marks a medication occurrence as taken through the verified action',
      () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'status': 'taken',
        'inventory_deduction': {
          'status': 'deducted',
          'message': '已记录服药，已扣减1片，精确库存剩余13片',
        },
      })
    ]);
    final api = ActionCenterApi(baseUrl: 'https://api.invalid', client: client);

    final result = await api.markMedicationTaken('occurrence-1');

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/medication/occurrences/occurrence-1/actions',
    );
    expect(client.requests.single.headers['Accept'], 'application/json');
    expect(client.requests.single.headers['Content-Type'], 'application/json');
    expect(jsonDecode(client.requestBodies.single), {'action': 'taken'});
    expect(result.message, '已记录服药，药箱余量已更新');
  });

  test('keeps medication action feedback simple when inventory is not deducted',
      () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'status': 'taken',
        'inventory_deduction': {
          'status': 'not_configured',
          'message': '已记录服药，但拜新同未记录每包装含量和剩余片数，无法自动扣减',
        },
      })
    ]);
    final api = ActionCenterApi(baseUrl: 'https://api.invalid', client: client);

    final result = await api.markMedicationTaken('occurrence-1');

    expect(result.message, '已记录服药');
  });

  test('handles an inventory batch expiry through the verified action',
      () async {
    final client = RecordingClient([
      jsonResponse(200, {'status': 'ok'})
    ]);
    final api = ActionCenterApi(baseUrl: 'https://api.invalid', client: client);

    await api.handleExpiryBatch('batch-1');

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/inventory-batches/batch-1/expiry-actions',
    );
    expect(jsonDecode(client.requestBodies.single), {'action': 'handled'});
  });

  test('handles a low stock alert through the verified action', () async {
    final client = RecordingClient([
      jsonResponse(200, {'status': 'ok'})
    ]);
    final api = ActionCenterApi(baseUrl: 'https://api.invalid', client: client);

    await api.handleLowStockAlert('alert-1');

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/low-stock-alerts/alert-1/actions',
    );
    expect(jsonDecode(client.requestBodies.single), {'action': 'handled'});
  });

  test('throws a stable exception when a verified action is rejected',
      () async {
    final api = ActionCenterApi(
      baseUrl: 'https://api.invalid',
      client: RecordingClient([
        jsonResponse(409, {'detail': 'already completed'})
      ]),
    );

    await expectLater(
      api.markMedicationTaken('occurrence-1'),
      throwsA(
        isA<ActionCenterApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
  });
}

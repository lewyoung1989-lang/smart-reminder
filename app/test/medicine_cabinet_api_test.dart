import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_cabinet_api.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/inventory_batch.dart';

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
  test('lists searched inventory and parses expiry state', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'next': 'https://api.invalid/api/v1/inventory-batches?cursor=next',
        'previous': null,
        'results': [
          {
            'id': 'batch-1',
            'medicine_id': 'medicine-1',
            'medicine_name': '布洛芬胶囊',
            'specification': '0.3g*20粒',
            'batch_number': 'LOT-88',
            'production_date': null,
            'expiry_date': '2026-08-20',
            'quantity': 2,
            'expiry_status': 'expiring_soon',
            'days_until_expiry': 15,
          },
        ],
      }),
    ]);
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final page = await api.listBatches(query: '布洛芬');

    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.url.path, '/api/v1/inventory-batches');
    expect(client.requests.single.url.queryParameters['q'], '布洛芬');
    expect(client.requests.single.headers['Authorization'], isNull);
    expect(page.batches.single.medicineName, '布洛芬胶囊');
    expect(
      page.batches.single.expiryStatus,
      InventoryExpiryStatus.expiringSoon,
    );
    expect(page.batches.single.productionDate, isNull);
    expect(page.batches.single.expiryDate, DateTime(2026, 8, 20));
    expect(page.nextPage?.queryParameters['cursor'], 'next');
  });

  test('follows only same-origin cursor URLs', () async {
    final client = RecordingClient([
      jsonResponse(200, {'next': null, 'previous': null, 'results': []}),
    ]);
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    await expectLater(
      api.listBatches(
        pageUrl: Uri.parse('https://other.invalid/inventory?cursor=stolen'),
      ),
      throwsA(isA<MedicineCabinetApiException>()),
    );
    expect(client.requests, isEmpty);

    await api.listBatches(
      pageUrl: Uri.parse(
        'https://api.invalid/api/v1/inventory-batches?cursor=next',
      ),
    );
    expect(client.requests.single.url.queryParameters['cursor'], 'next');
  });

  test('throws a stable exception for server errors', () async {
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: RecordingClient([
        jsonResponse(503, {'detail': 'unavailable'})
      ]),
    );

    await expectLater(
      api.listBatches(),
      throwsA(
        isA<MedicineCabinetApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });

  test('deletes one inventory batch through the shared client', () async {
    final client = RecordingClient([http.Response('', 204)]);
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    await api.deleteBatch('batch id/1');

    expect(client.requests.single.method, 'DELETE');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/inventory-batches/batch%20id%2F1',
    );
    expect(client.requests.single.headers['Authorization'], isNull);
  });

  test('throws a stable exception when batch deletion fails', () async {
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: RecordingClient([
        jsonResponse(500, {'detail': 'failed'})
      ]),
    );

    await expectLater(
      api.deleteBatch('batch-1'),
      throwsA(
        isA<MedicineCabinetApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });
}

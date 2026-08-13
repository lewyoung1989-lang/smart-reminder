import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_cabinet_api.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/inventory_batch.dart';

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
  test('parses a medicine description through the model draft endpoint',
      () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'medicine_name': '布洛芬胶囊',
        'specification': '0.3g*20粒',
        'batch_number': null,
        'production_date': null,
        'expiry_date': '2027-01-01',
        'quantity': 2,
        'ambiguities': ['批号未提供'],
      }),
    ]);
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final draft = await api.parseDescription(' 两盒布洛芬，明年元旦到期 ');

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.url.path,
      '/api/v1/inventory-batches/parse-description',
    );
    expect(jsonDecode(client.requestBodies.single), {
      'text': '两盒布洛芬，明年元旦到期',
    });
    expect(draft.medicineName, '布洛芬胶囊');
    expect(draft.quantity, 2);
    expect(draft.expiryDate, DateTime(2027, 1, 1));
    expect(draft.ambiguities, ['批号未提供']);
  });

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

  test('creates one inventory batch through the shared client', () async {
    final client = RecordingClient([
      jsonResponse(201, {
        'id': 'batch-1',
        'medicine_id': 'medicine-1',
        'medicine_name': '布洛芬胶囊',
        'specification': '0.3g*20粒',
        'batch_number': 'LOT-88',
        'production_date': '2026-01-01',
        'expiry_date': '2027-01-01',
        'quantity': 2,
        'expiry_status': 'valid',
        'days_until_expiry': 150,
      }),
    ]);
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final batch = await api.createBatch(
      medicineName: ' 布洛芬胶囊 ',
      specification: ' 0.3g*20粒 ',
      batchNumber: ' LOT-88 ',
      productionDate: DateTime(2026, 1, 1),
      expiryDate: DateTime(2027, 1, 1),
      quantity: 2,
    );

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/inventory-batches',
    );
    expect(client.requests.single.headers['Accept'], 'application/json');
    expect(client.requests.single.headers['Content-Type'], 'application/json');
    expect(jsonDecode(client.requestBodies.single), {
      'medicine_name': '布洛芬胶囊',
      'specification': '0.3g*20粒',
      'manufacturer': '',
      'photo_object_key': null,
      'batch_number': 'LOT-88',
      'production_date': '2026-01-01',
      'expiry_date': '2027-01-01',
      'quantity': 2,
    });
    expect(batch.medicineName, '布洛芬胶囊');
  });

  test('uploads an optional medicine photo before creating inventory',
      () async {
    final client = RecordingClient([
      jsonResponse(201, {
        'object_key': 'medicine-photos/user/photo.jpg',
        'upload_url': 'https://upload.invalid/photo.jpg',
        'headers': {'Content-Type': 'image/jpeg'},
        'expires_at': '2026-08-13T10:00:00Z',
      }),
      http.Response('', 200),
      jsonResponse(201, {
        'id': 'batch-1',
        'medicine_id': 'medicine-1',
        'medicine_name': '布洛芬胶囊',
        'specification': '0.3g*20粒',
        'manufacturer': '华北制药股份有限公司',
        'photo_url': 'https://download.invalid/photo.jpg',
        'batch_number': '',
        'production_date': null,
        'expiry_date': null,
        'quantity': 1,
        'expiry_status': 'unknown',
        'days_until_expiry': null,
      }),
    ]);
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final batch = await api.createBatch(
      medicineName: '布洛芬胶囊',
      specification: '0.3g*20粒',
      manufacturer: '华北制药股份有限公司',
      photoBytes: [1, 2, 3],
    );

    expect(client.requests.map((request) => request.method),
        ['POST', 'PUT', 'POST']);
    expect(client.requests[1].headers['Authorization'], isNull);
    expect(
        jsonDecode(client.requestBodies.last),
        containsPair(
          'photo_object_key',
          'medicine-photos/user/photo.jpg',
        ));
    expect(batch.manufacturer, '华北制药股份有限公司');
    expect(batch.photoUrl, 'https://download.invalid/photo.jpg');
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

  test('corrects one inventory batch expiry date through the shared client',
      () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'id': 'batch-1',
        'medicine_id': 'medicine-1',
        'medicine_name': '布洛芬胶囊',
        'specification': '0.3g*20粒',
        'batch_number': 'LOT-88',
        'production_date': null,
        'expiry_date': '2027-06-30',
        'quantity': 2,
        'expiry_status': 'valid',
        'days_until_expiry': 325,
      }),
    ]);
    final api = MedicineCabinetApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final batch = await api.correctExpiryDate(
      'batch id/1',
      expiryDate: DateTime(2027, 6, 30),
    );

    expect(client.requests.single.method, 'PATCH');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/inventory-batches/batch%20id%2F1/expiry-dates',
    );
    expect(client.requests.single.headers['Accept'], 'application/json');
    expect(client.requests.single.headers['Content-Type'], 'application/json');
    expect(jsonDecode(client.requestBodies.single), {
      'expiry_date': '2027-06-30',
    });
    expect(batch.expiryDate, DateTime(2027, 6, 30));
  });
}

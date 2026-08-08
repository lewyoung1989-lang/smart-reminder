import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/medicine_ocr/data/medicine_ocr_api.dart';

http.Response jsonResponse(int status, Map<String, Object?> body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response emptyResponse(int status) => http.Response('', status);

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

void main() {
  test('reads OCR capability before opening capture flow', () async {
    final client = RecordingClient([
      jsonResponse(200, {'enabled': false, 'code': 'ocr_disabled'}),
    ]);
    final api = MedicineOcrApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final enabled = await api.isEnabled();

    expect(enabled, isFalse);
    expect(client.requests.single.method, 'GET');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/ocr/capability',
    );
  });

  test('uploads two photos and creates an OCR job', () async {
    final client = RecordingClient([
      jsonResponse(201, {
        'object_key': 'front-key',
        'upload_url': 'https://upload.invalid/front',
        'headers': {'Content-Type': 'image/jpeg'},
        'expires_at': '2026-08-04T10:10:00Z',
      }),
      emptyResponse(200),
      jsonResponse(201, {
        'object_key': 'expiry-key',
        'upload_url': 'https://upload.invalid/expiry',
        'headers': {'Content-Type': 'image/jpeg'},
        'expires_at': '2026-08-04T10:10:00Z',
      }),
      emptyResponse(200),
      jsonResponse(201, {'id': 'job-1', 'status': 'queued'}),
    ]);
    final api = MedicineOcrApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final job = await api.createJob(
      frontBytes: [1, 2],
      expiryBytes: [3, 4],
    );

    expect(job.id, 'job-1');
    expect(
      client.requests.map((request) => request.method),
      ['POST', 'PUT', 'POST', 'PUT', 'POST'],
    );
    final storageRequests = client.requests.where(
      (request) => request.method == 'PUT',
    );
    expect(
      storageRequests.every(
        (request) => !request.headers.containsKey('Authorization'),
      ),
      isTrue,
    );
  });

  test('gets normalized candidate and confirms edited fields', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'id': 'job-1',
        'status': 'succeeded',
        'candidate': {
          'medicine_name': '布洛芬缓释胶囊',
          'specification': '0.3g*20粒',
          'batch_number': '20260108',
          'production_date': '2026-01-08',
          'expiry_date': '2028-05-31',
        },
      }),
      jsonResponse(201, {
        'medicine_id': 'medicine-1',
        'inventory_batch_id': 'batch-1',
        'status': 'confirmed',
      }),
    ]);
    final api = MedicineOcrApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );

    final job = await api.getJob('job-1');
    await api.confirmJob('job-1', {
      'medicine_name': '布洛芬胶囊',
      'quantity': 1,
    });

    expect(job.candidate?.medicineName, '布洛芬缓释胶囊');
    expect(job.candidate?.expiryDate, DateTime(2028, 5, 31));
    expect(client.requests.last.headers['Authorization'], isNull);
  });
}

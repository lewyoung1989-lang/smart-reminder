import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_reminder_app/features/medication/data/medication_api.dart';
import 'package:smart_reminder_app/features/medication/domain/medication_models.dart';

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
  test('creates a medication plan from a confirmed workflow draft', () async {
    final client = RecordingClient([
      jsonResponse(201, {
        'id': 'plan-1',
        'medicine_id': 'medicine-1',
        'dosage_text': '一次一片',
        'timezone': 'Asia/Shanghai',
        'times': ['08:00', '20:30'],
        'enabled': true,
      }),
    ]);
    final api = MedicationApi(baseUrl: 'https://api.invalid', client: client);

    final plan = await api.createPlan(
      workflowDraftId: 'draft-1',
      medicineId: 'medicine-1',
      dosageText: '一次一片',
      timezone: 'Asia/Shanghai',
      times: const ['08:00', '20:30'],
    );

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/medication/plans',
    );
    expect(jsonDecode(client.requestBodies.single), {
      'workflow_draft_id': 'draft-1',
      'medicine_id': 'medicine-1',
      'dosage_text': '一次一片',
      'timezone': 'Asia/Shanghai',
      'times': ['08:00', '20:30'],
    });
    expect(plan.id, 'plan-1');
    expect(plan.times, ['08:00', '20:30']);
    expect(plan.enabled, isTrue);
  });

  test(
      'creates a medication plan with medicine name when cabinet item is absent',
      () async {
    final client = RecordingClient([
      jsonResponse(201, {
        'id': 'plan-1',
        'medicine_id': null,
        'medicine_name': '依巴斯汀',
        'dosage_text': '一次一片',
        'timezone': 'Asia/Shanghai',
        'times': ['08:00'],
        'enabled': true,
      }),
    ]);
    final api = MedicationApi(baseUrl: 'https://api.invalid', client: client);

    final plan = await api.createPlan(
      workflowDraftId: 'draft-1',
      medicineName: '依巴斯汀',
      dosageText: '一次一片',
      timezone: 'Asia/Shanghai',
      times: const ['08:00'],
    );

    expect(jsonDecode(client.requestBodies.single), {
      'workflow_draft_id': 'draft-1',
      'medicine_name': '依巴斯汀',
      'dosage_text': '一次一片',
      'timezone': 'Asia/Shanghai',
      'times': ['08:00'],
    });
    expect(plan.medicineId, isNull);
  });

  test('lists pending medication occurrences', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'results': [
          {
            'id': 'occurrence-1',
            'plan_id': 'plan-1',
            'scheduled_at': '2026-08-08T08:00:00+08:00',
            'status': 'pending',
            'acted_at': null,
          },
        ],
      }),
    ]);
    final api = MedicationApi(baseUrl: 'https://api.invalid', client: client);

    final occurrences = await api.listPendingOccurrences();

    expect(client.requests.single.method, 'GET');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/medication/occurrences',
    );
    expect(occurrences.single.id, 'occurrence-1');
    expect(occurrences.single.status, MedicationOccurrenceStatus.pending);
    expect(
      occurrences.single.scheduledAt,
      DateTime.parse('2026-08-08T08:00:00+08:00'),
    );
  });

  test('records a medication occurrence action', () async {
    final client = RecordingClient([
      jsonResponse(200, {
        'id': 'occurrence-1',
        'plan_id': 'plan-1',
        'scheduled_at': '2026-08-08T08:00:00+08:00',
        'status': 'skipped',
        'acted_at': '2026-08-08T08:05:00+08:00',
      }),
    ]);
    final api = MedicationApi(baseUrl: 'https://api.invalid', client: client);

    final occurrence = await api.recordOccurrenceAction(
      'occurrence-1',
      MedicationOccurrenceAction.skipped,
    );

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.url.toString(),
      'https://api.invalid/api/v1/medication/occurrences/occurrence-1/actions',
    );
    expect(jsonDecode(client.requestBodies.single), {'action': 'skipped'});
    expect(occurrence.status, MedicationOccurrenceStatus.skipped);
    expect(occurrence.actedAt, DateTime.parse('2026-08-08T08:05:00+08:00'));
  });

  test('throws a stable exception for medication API errors', () async {
    final api = MedicationApi(
      baseUrl: 'https://api.invalid',
      client: RecordingClient([
        jsonResponse(409, {'code': 'medication_occurrence_already_actioned'})
      ]),
    );

    await expectLater(
      api.recordOccurrenceAction(
        'occurrence-1',
        MedicationOccurrenceAction.taken,
      ),
      throwsA(
        isA<MedicationApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
  });
}

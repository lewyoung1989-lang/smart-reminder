import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/medication_models.dart';

class MedicationApi {
  MedicationApi({
    required String baseUrl,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<MedicationPlan> createPlan({
    required String workflowDraftId,
    required String medicineId,
    required String dosageText,
    required String timezone,
    required List<String> times,
  }) async {
    final response = await _client.post(
      _baseUri.resolve('/api/v1/medication/plans'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'workflow_draft_id': workflowDraftId,
        'medicine_id': medicineId,
        'dosage_text': dosageText,
        'timezone': timezone,
        'times': times,
      }),
    );
    if (response.statusCode != 201) {
      throw MedicationApiException(response.statusCode, response.body);
    }
    return MedicationPlan.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<MedicationOccurrence>> listPendingOccurrences() async {
    final response = await _client.get(
      _baseUri.resolve('/api/v1/medication/occurrences'),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw MedicationApiException(response.statusCode, response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'] as List<dynamic>;
    return results
        .map(
          (value) =>
              MedicationOccurrence.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<MedicationOccurrence> recordOccurrenceAction(
    String occurrenceId,
    MedicationOccurrenceAction action,
  ) async {
    final response = await _client.post(
      _baseUri.resolve(
        '/api/v1/medication/occurrences/${Uri.encodeComponent(occurrenceId)}/actions',
      ),
      headers: _jsonHeaders,
      body: jsonEncode({
        'action': medicationOccurrenceActionValue(action),
      }),
    );
    if (response.statusCode != 200) {
      throw MedicationApiException(response.statusCode, response.body);
    }
    return MedicationOccurrence.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Map<String, String> get _jsonHeaders => const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  void close() {
    if (_ownsClient) _client.close();
  }
}

class MedicationApiException implements Exception {
  const MedicationApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'MedicationApiException($statusCode)';
}

import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class ActionCenterActions {
  Future<void> markMedicationTaken(String occurrenceId);

  Future<void> handleExpiryBatch(String batchId);
}

class ActionCenterApi implements ActionCenterActions {
  ActionCenterApi({
    required String baseUrl,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<void> markMedicationTaken(String occurrenceId) {
    return _postVerifiedAction(
      path:
          '/api/v1/medication/occurrences/${Uri.encodeComponent(occurrenceId)}/actions',
      action: 'taken',
    );
  }

  @override
  Future<void> handleExpiryBatch(String batchId) {
    return _postVerifiedAction(
      path:
          '/api/v1/inventory-batches/${Uri.encodeComponent(batchId)}/expiry-actions',
      action: 'handled',
    );
  }

  Future<void> _postVerifiedAction({
    required String path,
    required String action,
  }) async {
    final response = await _client.post(
      _baseUri.resolve(path),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'action': action}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ActionCenterApiException(response.statusCode, response.body);
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class ActionCenterApiException implements Exception {
  const ActionCenterApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ActionCenterApiException($statusCode)';
}

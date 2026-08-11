import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../quick_create/domain/quick_create_draft.dart';

class ReminderDraftApi {
  ReminderDraftApi({
    required this.baseUrl,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Future<QuickCreateDraft> createDraft(String text) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/reminder-drafts'),
      headers: _headers,
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode != 201) {
      throw ReminderDraftApiException(response.statusCode, response.body);
    }
    return QuickCreateDraft.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> confirmDraft(String draftId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/reminder-drafts/$draftId/confirm'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ReminderDraftApiException(response.statusCode, response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['reminder_id'] as String;
  }

  Future<String> confirmWorkflowDraft(String draftId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/workflow-drafts/$draftId/confirm'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ReminderDraftApiException(response.statusCode, response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['reminder_id'] as String;
  }

  Future<WorkflowDraft> answerWorkflowDraft(
    String draftId,
    String answer,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/workflow-drafts/$draftId/answers'),
      headers: _headers,
      body: jsonEncode({'answer': answer}),
    );
    if (response.statusCode != 200) {
      throw ReminderDraftApiException(response.statusCode, response.body);
    }
    return WorkflowDraft.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  void close() {
    if (_ownsClient) _client.close();
  }
}

class ReminderDraftApiException implements Exception {
  const ReminderDraftApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ReminderDraftApiException($statusCode)';
}

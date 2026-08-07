import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../reminder_drafts/domain/reminder_draft.dart';

class VoiceDraftApi {
  VoiceDraftApi({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String accessToken;
  final http.Client _client;

  Future<ReminderDraft> createDraft(String transcript) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/voice/reminder-drafts'),
      headers: _headers,
      body: jsonEncode({'transcript': transcript}),
    );
    if (response.statusCode != 201) {
      throw VoiceDraftApiException(response.statusCode, response.body);
    }
    return ReminderDraft.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> confirmDraft(String draftId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/voice/reminder-drafts/$draftId/confirm'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw VoiceDraftApiException(response.statusCode, response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['reminder_id'] as String;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  void close() => _client.close();
}

class VoiceDraftApiException implements Exception {
  const VoiceDraftApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'VoiceDraftApiException($statusCode)';
}

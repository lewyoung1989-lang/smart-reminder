import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/reminder.dart';

class ReminderApi {
  ReminderApi({
    required String baseUrl,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<ReminderPage> list({
    ReminderStatus status = ReminderStatus.pending,
    Uri? pageUrl,
  }) async {
    if (pageUrl != null && !_hasSameOrigin(pageUrl, _baseUri)) {
      throw const ReminderApiException(0, 'invalid_cursor_origin');
    }
    final uri = pageUrl ??
        _baseUri.resolve('/api/v1/reminders').replace(
          queryParameters: {'status': status.apiValue},
        );
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw ReminderApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'] as List<dynamic>;
    final next = payload['next'] as String?;
    return ReminderPage(
      reminders: results
          .map((value) => Reminder.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
      nextPage: next == null ? null : Uri.parse(next),
    );
  }

  Future<Reminder> cancel(String reminderId) async {
    final response = await _client.post(
      _baseUri.resolve('/api/v1/reminders/$reminderId/cancel'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ReminderApiException(response.statusCode, response.body);
    }
    return Reminder.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
      };

  static bool _hasSameOrigin(Uri candidate, Uri base) =>
      candidate.scheme == base.scheme &&
      candidate.host == base.host &&
      candidate.port == base.port;

  void close() {
    if (_ownsClient) _client.close();
  }
}

class ReminderApiException implements Exception {
  const ReminderApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  String? get code {
    try {
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['code'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'ReminderApiException($statusCode)';
}

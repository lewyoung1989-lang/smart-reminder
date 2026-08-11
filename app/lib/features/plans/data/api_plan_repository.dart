import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/plan_models.dart';
import 'plan_repository.dart';

class ApiPlanRepository implements PlanRepository {
  ApiPlanRepository({
    required String baseUrl,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<PlanCollection> load() async {
    final response = await _client.get(
      _baseUri.resolve('/api/v1/plans'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw PlanApiException(response.statusCode, response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'] as List<dynamic>? ?? const [];
    return PlanCollection(
      items: results
          .map((value) => _summary(value as Map<String, dynamic>))
          .toList(growable: false),
      isOffline: payload['is_offline'] == true,
    );
  }

  @override
  Future<PlanDetail> getById(String id) async {
    final response = await _client.get(
      _baseUri.resolve('/api/v1/plans/$id'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw PlanApiException(response.statusCode, response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return PlanDetail(
      summary: _summary(payload['summary'] as Map<String, dynamic>),
      arrivalLabel: payload['arrival_label'] as String?,
      destination: payload['destination'] as String?,
      queriedSources: List<String>.from(
        payload['queried_sources'] as List? ?? const [],
      ),
      reminderLabel: payload['reminder_label'] as String? ?? '按计划时间通知提醒',
      executions: (payload['executions'] as List? ?? const [])
          .map((value) => _execution(value as Map<String, dynamic>))
          .toList(growable: false),
      isDegraded: payload['is_degraded'] == true,
      degradationMessage: payload['degradation_message'] as String?,
    );
  }

  Map<String, String> get _headers => const {'Accept': 'application/json'};

  void close() {
    if (_ownsClient) _client.close();
  }
}

PlanSummary _summary(Map<String, dynamic> json) => PlanSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      nextRunAt: DateTime.parse(json['next_run_at'] as String).toLocal(),
      status: switch (json['status']) {
        'active' => PlanStatus.active,
        'pending' => PlanStatus.pending,
        'paused' => PlanStatus.paused,
        final value => throw FormatException('Unsupported plan status: $value'),
      },
      kind: switch (json['kind']) {
        'medication' => PlanKind.medication,
        'departure' => PlanKind.departure,
        'reminder' => PlanKind.reminder,
        final value => throw FormatException('Unsupported plan kind: $value'),
      },
    );

PlanExecution _execution(Map<String, dynamic> json) => PlanExecution(
      startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
      status: switch (json['status']) {
        'completed' => PlanExecutionStatus.completed,
        'degraded' => PlanExecutionStatus.degraded,
        'failed' => PlanExecutionStatus.failed,
        final value =>
          throw FormatException('Unsupported plan execution status: $value'),
      },
      message: json['message'] as String? ?? '',
    );

class PlanApiException implements Exception {
  const PlanApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'PlanApiException($statusCode)';
}

import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class ActionCenterActions {
  Future<MedicationActionResult> markMedicationTaken(String occurrenceId);

  Future<void> handleExpiryBatch(String batchId);

  Future<void> handleLowStockAlert(String alertId);

  Future<void> completeReminder(String reminderId);

  Future<void> snoozeReminder(String reminderId, {required int minutes});
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
  Future<MedicationActionResult> markMedicationTaken(
      String occurrenceId) async {
    final payload = await _postVerifiedAction(
      path:
          '/api/v1/medication/occurrences/${Uri.encodeComponent(occurrenceId)}/actions',
      action: 'taken',
    );
    return MedicationActionResult.fromJson(payload);
  }

  @override
  Future<void> handleExpiryBatch(String batchId) async {
    await _postVerifiedAction(
      path:
          '/api/v1/inventory-batches/${Uri.encodeComponent(batchId)}/expiry-actions',
      action: 'handled',
    );
  }

  @override
  Future<void> handleLowStockAlert(String alertId) async {
    await _postVerifiedAction(
      path: '/api/v1/low-stock-alerts/${Uri.encodeComponent(alertId)}/actions',
      action: 'handled',
    );
  }

  @override
  Future<void> completeReminder(String reminderId) async {
    await _postVerifiedAction(
      path: '/api/v1/reminders/${Uri.encodeComponent(reminderId)}/actions',
      action: 'complete',
    );
  }

  @override
  Future<void> snoozeReminder(String reminderId, {required int minutes}) async {
    await _postVerifiedAction(
      path: '/api/v1/reminders/${Uri.encodeComponent(reminderId)}/actions',
      action: 'snooze',
      extraBody: {'snooze_minutes': minutes},
    );
  }

  Future<Map<String, dynamic>> _postVerifiedAction({
    required String path,
    required String action,
    Map<String, Object?> extraBody = const {},
  }) async {
    final response = await _client.post(
      _baseUri.resolve(path),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'action': action, ...extraBody}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ActionCenterApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class MedicationActionResult {
  const MedicationActionResult({required this.message});

  factory MedicationActionResult.fromJson(Map<String, dynamic> json) {
    final deduction = json['inventory_deduction'];
    final deductionStatus = deduction is Map<String, dynamic>
        ? deduction['status'] as String?
        : null;
    final deductionMessage = deduction is Map<String, dynamic>
        ? deduction['message'] as String?
        : null;
    return MedicationActionResult(
      message: deductionMessage != null && deductionMessage.isNotEmpty
          ? deductionMessage
          : deductionStatus == 'deducted'
              ? '已记录服药，药箱余量已更新'
              : '已记录服药',
    );
  }

  final String message;
}

class ActionCenterApiException implements Exception {
  ActionCenterApiException(this.statusCode, this.body) : code = _code(body);

  final int statusCode;
  final String body;
  final String? code;

  String get userMessage {
    if (code == 'medication_occurrence_already_actioned') {
      return '这条用药提醒已处理，正在刷新';
    }
    if (statusCode == 404) return '这条提醒状态已变化，正在刷新';
    return '处理失败，请稍后重试';
  }

  @override
  String toString() => 'ActionCenterApiException($statusCode)';

  static String? _code(String body) {
    try {
      final payload = jsonDecode(body);
      if (payload is Map<String, dynamic>) {
        final code = payload['code'];
        return code is String ? code : null;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

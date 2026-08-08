import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/data/feature_unavailable_exception.dart';
import '../domain/today_models.dart';

abstract interface class TodayRepository {
  Future<TodaySnapshot> load();
}

class ApiTodayRepository implements TodayRepository {
  ApiTodayRepository({
    required String baseUrl,
    http.Client? client,
  })  : _baseUrl = baseUrl,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<TodaySnapshot> load() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/v1/action-center/today'),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw TodayApiException(response.statusCode, response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return TodaySnapshot(
      decisions: _items(payload['need_decision'])
          .map(_attentionItem)
          .toList(growable: false),
      timeline: _items(payload['upcoming'])
          .map(_timelineItem)
          .toList(growable: false),
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class DemoTodayRepository implements TodayRepository {
  DemoTodayRepository({required this.now});

  final DateTime now;

  DateTime _at(int hour, [int minute = 0]) {
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  @override
  Future<TodaySnapshot> load() async {
    return TodaySnapshot(
      decisions: [
        AttentionItem(
          id: 'departure-weather',
          title: '工作日出门',
          reason: '天气服务暂时不可用，请确认出发时间',
          dueAt: _at(8),
          kind: AttentionKind.degraded,
          actionLabel: '查看详情',
        ),
        AttentionItem(
          id: 'demo-car-wash',
          title: '洗车计划',
          reason: '仅用于演示待确认流程，不代表已接入生产能力',
          dueAt: _at(18),
          kind: AttentionKind.confirmation,
          actionLabel: '确认',
        ),
      ],
      timeline: [
        TimelineItem(
          id: 'morning-medication',
          title: '早间用药',
          subtitle: '布洛芬缓释胶囊',
          scheduledAt: _at(8),
          status: TimelineStatus.completed,
        ),
        TimelineItem(
          id: 'workday-departure',
          title: '工作日出门',
          subtitle: '天气服务降级，路线提醒仍可用',
          scheduledAt: _at(8, 5),
          status: TimelineStatus.completed,
        ),
        TimelineItem(
          id: 'medicine-expiry',
          title: '药品临期',
          subtitle: '布洛芬缓释胶囊将在 30 天内到期',
          scheduledAt: _at(14),
          status: TimelineStatus.upcoming,
        ),
        TimelineItem(
          id: 'evening-reminder',
          title: '晚间提醒',
          subtitle: '给家人打电话',
          scheduledAt: _at(20),
          status: TimelineStatus.upcoming,
        ),
      ],
    );
  }
}

class UnavailableTodayRepository implements TodayRepository {
  const UnavailableTodayRepository();

  @override
  Future<TodaySnapshot> load() {
    return Future.error(const FeatureUnavailableException('today'));
  }
}

class TodayApiException implements Exception {
  const TodayApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'TodayApiException($statusCode)';
}

List<Map<String, dynamic>> _items(Object? page) {
  if (page is! Map<String, dynamic>) return const [];
  final results = page['results'];
  if (results is! List) return const [];
  return results.cast<Map<String, dynamic>>();
}

AttentionItem _attentionItem(Map<String, dynamic> json) {
  final kind = json['kind'] as String? ?? '';
  final status = json['status'] as String? ?? '';
  return AttentionItem(
    id: json['id'] as String,
    title: json['title'] as String,
    reason: _attentionReason(kind, status),
    dueAt: _parseActionCenterTime(json['occurred_at']),
    kind: _attentionKind(kind, status),
    actionLabel: _attentionActionLabel(kind, status),
    actionTarget: _actionTarget(json['action_target']),
  );
}

TimelineItem _timelineItem(Map<String, dynamic> json) {
  final kind = json['kind'] as String? ?? '';
  final status = json['status'] as String? ?? '';
  return TimelineItem(
    id: json['id'] as String,
    title: json['title'] as String,
    subtitle: _timelineSubtitle(kind, status),
    scheduledAt: _parseActionCenterTime(json['occurred_at']),
    status: _timelineStatus(status),
  );
}

DateTime _parseActionCenterTime(Object? value) {
  if (value is! String || value.isEmpty) return DateTime.now();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return DateTime.parse('${value}T00:00:00');
  }
  return DateTime.parse(value);
}

AttentionKind _attentionKind(String kind, String status) {
  if (kind == 'delivery' || status == 'failed') return AttentionKind.degraded;
  if (status == 'paused') return AttentionKind.permission;
  return AttentionKind.confirmation;
}

String _attentionActionLabel(String kind, String status) {
  if (kind == 'medication') return '记录';
  if (kind == 'medicine_expiry') return '处理';
  if (status == 'paused') return '查看';
  return '查看详情';
}

String _attentionReason(String kind, String status) {
  if (kind == 'medication') return '已到服药时间，请确认是否已服用';
  if (kind == 'medicine_expiry') return '药品有效期需要确认';
  if (kind == 'delivery') return '通知发送失败，需要稍后重试或检查设置';
  if (status == 'paused') return '工作流已暂停，需要你确认后继续';
  return '需要你确认下一步';
}

TimelineStatus _timelineStatus(String status) {
  if (status == 'pending') return TimelineStatus.due;
  if (status == 'skipped') return TimelineStatus.skipped;
  if (status == 'completed') return TimelineStatus.completed;
  return TimelineStatus.upcoming;
}

String _timelineSubtitle(String kind, String status) {
  if (kind == 'medication') return '用药计划';
  if (kind == 'medicine_expiry') return '药品有效期';
  if (kind == 'delivery') return '通知队列';
  if (kind == 'workflow') return status == 'scheduled' ? '已安排' : '工作流';
  return status;
}

ActionTarget? _actionTarget(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final resource = value['resource'];
  final id = value['id'];
  if (resource is! String || id is! String) return null;
  return ActionTarget(resource: resource, id: id);
}

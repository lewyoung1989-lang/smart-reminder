import 'package:smart_reminder_app/core/data/feature_unavailable_exception.dart';
import 'package:smart_reminder_app/features/plans/data/plan_repository.dart';
import 'package:smart_reminder_app/features/plans/domain/plan_models.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/today/data/today_repository.dart';
import 'package:smart_reminder_app/features/today/domain/today_models.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';

final fixedNow = DateTime(2026, 8, 6, 9, 30);

final testDraft = ReminderDraft(
  id: 'draft-1',
  title: '喝水',
  scheduledAt: DateTime(2026, 8, 6, 10),
  timezone: 'Asia/Shanghai',
  severity: ReminderSeverity.notification,
  weatherMessage: null,
  ambiguities: const [],
  parserSource: 'local',
);

final departureDetail = PlanDetail(
  summary: PlanSummary(
    id: 'workday-departure',
    title: '工作日出门',
    subtitle: '根据路线和天气动态提醒',
    nextRunAt: DateTime(2026, 8, 7, 8, 5),
    status: PlanStatus.active,
    kind: PlanKind.departure,
  ),
  arrivalLabel: '08:45 公司',
  destination: '公司',
  queriedSources: const ['路线', '天气'],
  reminderLabel: '提前 40 分钟提醒',
  executions: [
    PlanExecution(
      startedAt: DateTime(2026, 8, 6, 8, 4),
      status: PlanExecutionStatus.degraded,
      message: '已按实时路况提醒',
    ),
  ],
  isDegraded: true,
  degradationMessage: '天气服务暂时不可用，已仅根据路线估算',
);

class FakeTodayRepository implements TodayRepository {
  FakeTodayRepository._({this.snapshot, this.error});

  factory FakeTodayRepository.success({TodaySnapshot? snapshot}) {
    return FakeTodayRepository._(
      snapshot: snapshot ?? _todaySnapshot(isOffline: false),
    );
  }

  factory FakeTodayRepository.cachedOffline({TodaySnapshot? snapshot}) {
    return FakeTodayRepository._(
      snapshot: snapshot ?? _todaySnapshot(isOffline: true),
    );
  }

  factory FakeTodayRepository.empty() {
    return FakeTodayRepository._(
      snapshot: TodaySnapshot(decisions: const [], timeline: const []),
    );
  }

  factory FakeTodayRepository.error([Object? error]) {
    return FakeTodayRepository._(error: error ?? StateError('today failed'));
  }

  factory FakeTodayRepository.unavailable() {
    return FakeTodayRepository._(
      error: const FeatureUnavailableException('today'),
    );
  }

  final TodaySnapshot? snapshot;
  final Object? error;

  @override
  Future<TodaySnapshot> load() async {
    if (error case final value?) throw value;
    return snapshot!;
  }
}

TodaySnapshot _todaySnapshot({required bool isOffline}) {
  return TodaySnapshot(
    decisions: [
      AttentionItem(
        id: 'departure-weather',
        title: '工作日出门',
        reason: '天气服务暂时不可用，请确认出发时间',
        dueAt: DateTime(2026, 8, 6, 8),
        kind: AttentionKind.degraded,
        actionLabel: '查看详情',
      ),
      AttentionItem(
        id: 'demo-car-wash',
        title: '洗车计划',
        reason: '仅用于演示待确认流程，不代表已接入生产能力',
        dueAt: DateTime(2026, 8, 6, 18),
        kind: AttentionKind.confirmation,
        actionLabel: '确认',
      ),
    ],
    timeline: [
      TimelineItem(
        id: 'morning-medication',
        title: '早间用药',
        subtitle: '布洛芬缓释胶囊',
        scheduledAt: DateTime(2026, 8, 6, 8),
        status: TimelineStatus.completed,
      ),
      TimelineItem(
        id: 'workday-departure',
        title: '工作日出门',
        subtitle: '天气服务降级，路线提醒仍可用',
        scheduledAt: DateTime(2026, 8, 6, 8, 5),
        status: TimelineStatus.completed,
      ),
      TimelineItem(
        id: 'medicine-expiry',
        title: '药品临期',
        subtitle: '布洛芬缓释胶囊将在 30 天内到期',
        scheduledAt: DateTime(2026, 8, 6, 14),
        status: TimelineStatus.upcoming,
        actionTarget: const ActionTarget(
          resource: 'inventory_batch',
          id: 'batch-1',
        ),
      ),
      TimelineItem(
        id: 'evening-reminder',
        title: '晚间提醒',
        subtitle: '给家人打电话',
        scheduledAt: DateTime(2026, 8, 6, 20),
        status: TimelineStatus.upcoming,
      ),
    ],
    isOffline: isOffline,
  );
}

class FakePlanRepository implements PlanRepository {
  FakePlanRepository._({
    required this.collection,
    required this.details,
    this.error,
  });

  factory FakePlanRepository.success() {
    return FakePlanRepository._(
      collection: PlanCollection(items: [departureDetail.summary]),
      details: {departureDetail.summary.id: departureDetail},
    );
  }

  factory FakePlanRepository.cachedOffline() {
    return FakePlanRepository._(
      collection: PlanCollection(
        items: [departureDetail.summary],
        isOffline: true,
      ),
      details: {departureDetail.summary.id: departureDetail},
    );
  }

  factory FakePlanRepository.empty() {
    return FakePlanRepository._(
      collection: PlanCollection(items: const []),
      details: const {},
    );
  }

  factory FakePlanRepository.error([Object? error]) {
    return FakePlanRepository._(
      collection: PlanCollection(items: const []),
      details: const {},
      error: error ?? StateError('plans failed'),
    );
  }

  factory FakePlanRepository.unavailable() {
    return FakePlanRepository.error(
      const FeatureUnavailableException('plans'),
    );
  }

  final PlanCollection collection;
  final Map<String, PlanDetail> details;
  final Object? error;

  @override
  Future<PlanDetail> getById(String id) async {
    if (error case final value?) throw value;
    final detail = details[id];
    if (detail == null) throw StateError('Unknown plan id: $id');
    return detail;
  }

  @override
  Future<PlanCollection> load() async {
    if (error case final value?) throw value;
    return collection;
  }
}

class RecordingNotificationScheduler implements ReminderNotificationScheduler {
  RecordingNotificationScheduler({this.error});

  final requests = <({String reminderId, ReminderDraft draft})>[];
  Object? error;

  @override
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  }) async {
    requests.add((reminderId: reminderId, draft: draft));
    if (error case final value?) throw value;
  }

  @override
  Future<void> cancel({required String reminderId}) async {}
}

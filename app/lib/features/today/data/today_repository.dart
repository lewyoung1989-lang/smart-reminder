import '../../../core/data/feature_unavailable_exception.dart';
import '../domain/today_models.dart';

abstract interface class TodayRepository {
  Future<TodaySnapshot> load();
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

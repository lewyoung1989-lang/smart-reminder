import '../../../core/data/feature_unavailable_exception.dart';
import '../domain/plan_models.dart';

abstract interface class PlanRepository {
  Future<PlanCollection> load();

  Future<PlanDetail> getById(String id);
}

abstract interface class PlanActions {
  Future<PlanDetail> pause(String id);

  Future<PlanDetail> resume(String id);

  Future<void> delete(String id);
}

class DemoPlanRepository implements PlanRepository {
  DemoPlanRepository({required this.now});

  final DateTime now;

  DateTime _at(int dayOffset, int hour, [int minute = 0]) {
    return DateTime(now.year, now.month, now.day + dayOffset, hour, minute);
  }

  DateTime _nextDaily(int hour, [int minute = 0]) {
    final today = _at(0, hour, minute);
    return today.isBefore(now) ? _at(1, hour, minute) : today;
  }

  DateTime _nextWorkday(int hour, [int minute = 0]) {
    var candidate = _nextDaily(hour, minute);
    while (candidate.weekday == DateTime.saturday ||
        candidate.weekday == DateTime.sunday) {
      candidate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day + 1,
        hour,
        minute,
      );
    }
    return candidate;
  }

  DateTime _nextFollowingWorkday(int hour, [int minute = 0]) {
    var candidate = _at(1, hour, minute);
    while (candidate.weekday == DateTime.saturday ||
        candidate.weekday == DateTime.sunday) {
      candidate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day + 1,
        hour,
        minute,
      );
    }
    return candidate;
  }

  DateTime _nextWeekday(int weekday, int hour, [int minute = 0]) {
    var dayOffset =
        (weekday - now.weekday + DateTime.daysPerWeek) % DateTime.daysPerWeek;
    var candidate = _at(dayOffset, hour, minute);
    if (candidate.isBefore(now)) {
      dayOffset += DateTime.daysPerWeek;
      candidate = _at(dayOffset, hour, minute);
    }
    return candidate;
  }

  DateTime _nextMonthly(int day, int hour, [int minute = 0]) {
    final thisMonth = DateTime(now.year, now.month, day, hour, minute);
    if (!thisMonth.isBefore(now)) return thisMonth;
    return DateTime(now.year, now.month + 1, day, hour, minute);
  }

  DateTime _mostRecentDaily(int hour, [int minute = 0]) {
    final today = _at(0, hour, minute);
    return today.isAfter(now) ? _at(-1, hour, minute) : today;
  }

  DateTime _mostRecentWorkday(int hour, [int minute = 0]) {
    var candidate = _mostRecentDaily(hour, minute);
    while (candidate.weekday == DateTime.saturday ||
        candidate.weekday == DateTime.sunday) {
      candidate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day - 1,
        hour,
        minute,
      );
    }
    return candidate;
  }

  List<PlanSummary> _summaries() {
    return [
      PlanSummary(
        id: 'workday-departure',
        title: '工作日出门',
        subtitle: '根据路线和天气动态提醒',
        nextRunAt: _nextWorkday(8, 5),
        status: PlanStatus.active,
        kind: PlanKind.departure,
      ),
      PlanSummary(
        id: 'morning-medication',
        title: '早间用药',
        subtitle: '布洛芬缓释胶囊',
        nextRunAt: _nextDaily(8),
        status: PlanStatus.pending,
        kind: PlanKind.medication,
      ),
      PlanSummary(
        id: 'evening-blood-pressure',
        title: '晚间血压记录',
        subtitle: '每天睡前记录',
        nextRunAt: _nextDaily(21),
        status: PlanStatus.active,
        kind: PlanKind.reminder,
      ),
      PlanSummary(
        id: 'weekend-vitamins',
        title: '周末维生素',
        subtitle: '周六早餐后',
        nextRunAt: _nextWeekday(DateTime.saturday, 9),
        status: PlanStatus.active,
        kind: PlanKind.medication,
      ),
      PlanSummary(
        id: 'rent-reminder',
        title: '房租提醒',
        subtitle: '每月 25 日',
        nextRunAt: _nextMonthly(25, 10),
        status: PlanStatus.active,
        kind: PlanKind.reminder,
      ),
      PlanSummary(
        id: 'recycling-reminder',
        title: '回收物投放',
        subtitle: '每周三晚间',
        nextRunAt: _nextWeekday(DateTime.wednesday, 19),
        status: PlanStatus.active,
        kind: PlanKind.reminder,
      ),
      PlanSummary(
        id: 'family-call',
        title: '联系家人',
        subtitle: '每周日晚间',
        nextRunAt: _nextWeekday(DateTime.sunday, 20),
        status: PlanStatus.active,
        kind: PlanKind.reminder,
      ),
      PlanSummary(
        id: 'hydration-break',
        title: '工作间歇喝水',
        subtitle: '工作日上午每两小时',
        nextRunAt: _nextFollowingWorkday(10),
        status: PlanStatus.paused,
        kind: PlanKind.reminder,
      ),
    ];
  }

  @override
  Future<PlanCollection> load() async {
    return PlanCollection(items: _summaries());
  }

  @override
  Future<PlanDetail> getById(String id) async {
    final summaries = _summaries();
    final matches = summaries.where((summary) => summary.id == id);
    if (matches.isEmpty) throw StateError('Unknown plan id: $id');
    final summary = matches.single;

    if (id == 'workday-departure') {
      return PlanDetail(
        summary: summary,
        arrivalLabel: '08:45 公司',
        destination: '公司',
        queriedSources: const ['路线', '天气'],
        reminderLabel: '提前 40 分钟提醒',
        executions: [
          PlanExecution(
            startedAt: _mostRecentWorkday(8, 4),
            status: PlanExecutionStatus.degraded,
            message: '已按实时路况提醒',
          ),
        ],
        isDegraded: true,
        degradationMessage: '天气服务暂时不可用，已仅根据路线估算',
      );
    }

    if (id == 'morning-medication') {
      return PlanDetail(
        summary: summary,
        queriedSources: const [],
        reminderLabel: '每天 08:00 通知提醒',
        executions: [
          PlanExecution(
            startedAt: _mostRecentDaily(8),
            status: PlanExecutionStatus.completed,
            message: '已确认完成',
          ),
        ],
      );
    }

    return PlanDetail(
      summary: summary,
      queriedSources: const [],
      reminderLabel: '按计划时间通知提醒',
      executions: const [],
    );
  }
}

class UnavailablePlanRepository implements PlanRepository {
  const UnavailablePlanRepository();

  @override
  Future<PlanCollection> load() {
    return Future.error(const FeatureUnavailableException('plans'));
  }

  @override
  Future<PlanDetail> getById(String id) {
    return Future.error(const FeatureUnavailableException('plans'));
  }
}

import '../../features/plans/domain/plan_models.dart';
import '../../features/reminder_drafts/domain/reminder_draft.dart'
    as draft_models;
import '../../features/reminders/domain/reminder.dart' as reminder_models;
import 'local_notification_scheduler.dart';
import 'reminder_notification_scheduler.dart';

typedef PendingReminderLoader = Future<reminder_models.ReminderPage> Function({
  reminder_models.ReminderStatus status,
  Uri? pageUrl,
});

typedef PlanCollectionLoader = Future<PlanCollection> Function();
typedef PlanDetailLoader = Future<PlanDetail> Function(String id);

class NotificationSyncResult {
  const NotificationSyncResult({
    required this.remindersScheduled,
    required this.plansScheduled,
    required this.failures,
  });

  final int remindersScheduled;
  final int plansScheduled;
  final int failures;
}

class NotificationSyncService {
  const NotificationSyncService({
    required this.listReminders,
    required this.loadPlans,
    required this.loadPlanDetail,
    required this.reminderScheduler,
    required this.planScheduler,
    DateTime Function()? now,
    this.maxReminderPages = 4,
    this.maxPlans = 50,
  }) : _now = now ?? DateTime.now;

  final PendingReminderLoader listReminders;
  final PlanCollectionLoader loadPlans;
  final PlanDetailLoader loadPlanDetail;
  final ReminderNotificationScheduler reminderScheduler;
  final PlanNotificationScheduler? planScheduler;
  final DateTime Function() _now;
  final int maxReminderPages;
  final int maxPlans;

  Future<NotificationSyncResult> syncUpcoming() async {
    var remindersScheduled = 0;
    var plansScheduled = 0;
    var failures = 0;

    final reminderResult = await _syncReminders();
    remindersScheduled += reminderResult.scheduled;
    failures += reminderResult.failures;

    final planResult = await _syncPlans();
    plansScheduled += planResult.scheduled;
    failures += planResult.failures;

    return NotificationSyncResult(
      remindersScheduled: remindersScheduled,
      plansScheduled: plansScheduled,
      failures: failures,
    );
  }

  Future<_SyncCount> _syncReminders() async {
    var scheduled = 0;
    var failures = 0;
    Uri? pageUrl;
    for (var pageIndex = 0; pageIndex < maxReminderPages; pageIndex++) {
      final page = await listReminders(
        status: reminder_models.ReminderStatus.pending,
        pageUrl: pageUrl,
      );
      for (final reminder in page.reminders) {
        if (reminder.status != reminder_models.ReminderStatus.pending ||
            !reminder.scheduledAt.isAfter(_now())) {
          continue;
        }
        try {
          await reminderScheduler.schedule(
            reminderId: reminder.id,
            draft: _draftFromReminder(reminder),
          );
          scheduled += 1;
        } on ReminderNotificationException {
          failures += 1;
        }
      }
      pageUrl = page.nextPage;
      if (pageUrl == null) break;
    }
    return _SyncCount(scheduled: scheduled, failures: failures);
  }

  Future<_SyncCount> _syncPlans() async {
    final scheduler = planScheduler;
    if (scheduler == null) {
      return const _SyncCount(scheduled: 0, failures: 0);
    }
    final collection = await loadPlans();
    var scheduled = 0;
    var failures = 0;
    final activePlans = collection.items
        .where((plan) => plan.status == PlanStatus.active)
        .take(maxPlans);
    for (final plan in activePlans) {
      try {
        final detail = await loadPlanDetail(plan.id);
        final schedule = _futureSchedule(detail.notificationSchedule);
        if (schedule == null) continue;
        await scheduler.schedulePlan(planId: plan.id, schedule: schedule);
        scheduled += 1;
      } on ReminderNotificationException {
        failures += 1;
      } catch (_) {
        failures += 1;
      }
    }
    return _SyncCount(scheduled: scheduled, failures: failures);
  }

  PlanNotificationSchedule? _futureSchedule(
    PlanNotificationSchedule? schedule,
  ) {
    if (schedule == null) return null;
    final now = _now();
    final futureTimes = schedule.scheduledTimes
        .where((scheduledAt) => scheduledAt.isAfter(now))
        .toList(growable: false);
    if (futureTimes.isEmpty) return null;
    if (schedule.repeat == PlanRepeat.none && futureTimes.length != 1) {
      return null;
    }
    return PlanNotificationSchedule(
      scheduledTimes: futureTimes,
      repeat: schedule.repeat,
      title: schedule.title,
      timezone: schedule.timezone,
    );
  }

  draft_models.ReminderDraft _draftFromReminder(
    reminder_models.Reminder reminder,
  ) {
    return draft_models.ReminderDraft(
      id: 'sync:${reminder.id}',
      title: reminder.title,
      scheduledAt: reminder.scheduledAt,
      timezone: reminder.timezone,
      severity: switch (reminder.severity) {
        reminder_models.ReminderSeverity.alarm =>
          draft_models.ReminderSeverity.alarm,
        reminder_models.ReminderSeverity.notification =>
          draft_models.ReminderSeverity.notification,
      },
      weatherMessage: null,
      ambiguities: const [],
      parserSource: 'server-sync',
    );
  }
}

class _SyncCount {
  const _SyncCount({required this.scheduled, required this.failures});

  final int scheduled;
  final int failures;
}

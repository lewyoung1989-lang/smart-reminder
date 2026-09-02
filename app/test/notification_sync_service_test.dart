import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/plans/domain/plan_models.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/reminders/domain/reminder.dart'
    as reminder_models;
import 'package:smart_reminder_app/platform/notifications/local_notification_scheduler.dart';
import 'package:smart_reminder_app/platform/notifications/notification_sync_service.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';

void main() {
  final now = DateTime(2026, 9, 2, 9);

  reminder_models.Reminder reminder({
    required String id,
    required DateTime scheduledAt,
    reminder_models.ReminderStatus status =
        reminder_models.ReminderStatus.pending,
  }) {
    return reminder_models.Reminder(
      id: id,
      title: '喝水',
      timezone: 'Asia/Shanghai',
      scheduledAt: scheduledAt,
      severity: reminder_models.ReminderSeverity.notification,
      status: status,
      cancelledAt: null,
      completedAt: null,
    );
  }

  PlanSummary planSummary({
    required String id,
    PlanStatus status = PlanStatus.active,
  }) {
    return PlanSummary(
      id: id,
      title: '用药提醒',
      subtitle: '拜新同 · 1片',
      nextRunAt: DateTime(2026, 9, 2, 21),
      status: status,
      kind: PlanKind.medication,
    );
  }

  PlanDetail planDetail(String id) {
    return PlanDetail(
      summary: planSummary(id: id),
      queriedSources: const [],
      reminderLabel: '每天 21:00 通知提醒',
      executions: const [],
      notificationSchedule: PlanNotificationSchedule(
        scheduledAt: DateTime(2026, 9, 2, 21),
        repeat: PlanRepeat.daily,
        title: '用药提醒',
        timezone: 'Asia/Shanghai',
      ),
    );
  }

  test('automatically schedules upcoming reminders and active plans', () async {
    final scheduler = _RecordingScheduler();
    final service = NotificationSyncService(
      now: () => now,
      reminderScheduler: scheduler,
      planScheduler: scheduler,
      listReminders: (
          {status = reminder_models.ReminderStatus.pending, pageUrl}) async {
        return reminder_models.ReminderPage(
          reminders: [
            reminder(id: 'reminder-1', scheduledAt: DateTime(2026, 9, 2, 10)),
          ],
          nextPage: null,
        );
      },
      loadPlans: () async => PlanCollection(
        items: [planSummary(id: 'plan-1')],
      ),
      loadPlanDetail: (id) async => planDetail(id),
    );

    final result = await service.syncUpcoming();

    expect(result.remindersScheduled, 1);
    expect(result.plansScheduled, 1);
    expect(result.failures, 0);
    expect(scheduler.reminderIds, ['reminder-1']);
    expect(scheduler.reminderDrafts.single.title, '喝水');
    expect(scheduler.planIds, ['plan-1']);
  });

  test('skips stale reminders and paused plans during automatic sync',
      () async {
    final scheduler = _RecordingScheduler();
    final service = NotificationSyncService(
      now: () => now,
      reminderScheduler: scheduler,
      planScheduler: scheduler,
      listReminders: (
          {status = reminder_models.ReminderStatus.pending, pageUrl}) async {
        return reminder_models.ReminderPage(
          reminders: [
            reminder(id: 'past-reminder', scheduledAt: DateTime(2026, 9, 2, 8)),
          ],
          nextPage: null,
        );
      },
      loadPlans: () async => PlanCollection(
        items: [planSummary(id: 'paused-plan', status: PlanStatus.paused)],
      ),
      loadPlanDetail: (id) async => planDetail(id),
    );

    final result = await service.syncUpcoming();

    expect(result.remindersScheduled, 0);
    expect(result.plansScheduled, 0);
    expect(result.failures, 0);
    expect(scheduler.reminderIds, isEmpty);
    expect(scheduler.planIds, isEmpty);
  });

  test('schedules only future time points from the current day baseline',
      () async {
    final scheduler = _RecordingScheduler();
    final detail = PlanDetail(
      summary: planSummary(id: 'plan-1'),
      queriedSources: const [],
      reminderLabel: '每天 08:00、13:00、20:00 通知提醒',
      executions: const [],
      notificationSchedule: PlanNotificationSchedule(
        scheduledTimes: [
          DateTime(2026, 9, 2, 8),
          DateTime(2026, 9, 2, 13),
          DateTime(2026, 9, 2, 20),
        ],
        repeat: PlanRepeat.daily,
        title: '用药提醒',
        timezone: 'Asia/Shanghai',
      ),
    );
    final service = NotificationSyncService(
      now: () => DateTime(2026, 9, 2, 16, 57),
      reminderScheduler: scheduler,
      planScheduler: scheduler,
      listReminders: (
          {status = reminder_models.ReminderStatus.pending, pageUrl}) async {
        return const reminder_models.ReminderPage(
          reminders: [],
          nextPage: null,
        );
      },
      loadPlans: () async => PlanCollection(
        items: [planSummary(id: 'plan-1')],
      ),
      loadPlanDetail: (_) async => detail,
    );

    final result = await service.syncUpcoming();

    expect(result.plansScheduled, 1);
    expect(scheduler.planSchedules.single.scheduledTimes, [
      DateTime(2026, 9, 2, 20),
    ]);
  });

  test('skips a plan when all returned time points are already stale',
      () async {
    final scheduler = _RecordingScheduler();
    final detail = PlanDetail(
      summary: planSummary(id: 'plan-1'),
      queriedSources: const [],
      reminderLabel: '每天 08:00 通知提醒',
      executions: const [],
      notificationSchedule: PlanNotificationSchedule(
        scheduledAt: DateTime(2026, 9, 2, 8),
        repeat: PlanRepeat.daily,
        title: '用药提醒',
        timezone: 'Asia/Shanghai',
      ),
    );
    final service = NotificationSyncService(
      now: () => DateTime(2026, 9, 2, 16, 57),
      reminderScheduler: scheduler,
      planScheduler: scheduler,
      listReminders: (
          {status = reminder_models.ReminderStatus.pending, pageUrl}) async {
        return const reminder_models.ReminderPage(
          reminders: [],
          nextPage: null,
        );
      },
      loadPlans: () async => PlanCollection(
        items: [planSummary(id: 'plan-1')],
      ),
      loadPlanDetail: (_) async => detail,
    );

    final result = await service.syncUpcoming();

    expect(result.plansScheduled, 0);
    expect(scheduler.planSchedules, isEmpty);
  });

  test(
      'continues syncing other items when one notification cannot be scheduled',
      () async {
    final scheduler = _RecordingScheduler()
      ..failReminderIds.add('bad-reminder');
    final service = NotificationSyncService(
      now: () => now,
      reminderScheduler: scheduler,
      planScheduler: scheduler,
      listReminders: (
          {status = reminder_models.ReminderStatus.pending, pageUrl}) async {
        return reminder_models.ReminderPage(
          reminders: [
            reminder(id: 'bad-reminder', scheduledAt: DateTime(2026, 9, 2, 10)),
            reminder(
                id: 'good-reminder', scheduledAt: DateTime(2026, 9, 2, 11)),
          ],
          nextPage: null,
        );
      },
      loadPlans: () async => PlanCollection(items: const []),
      loadPlanDetail: (id) async => planDetail(id),
    );

    final result = await service.syncUpcoming();

    expect(result.remindersScheduled, 1);
    expect(result.failures, 1);
    expect(scheduler.reminderIds, ['good-reminder']);
  });
}

class _RecordingScheduler
    implements ReminderNotificationScheduler, PlanNotificationScheduler {
  final reminderIds = <String>[];
  final reminderDrafts = <ReminderDraft>[];
  final planIds = <String>[];
  final planSchedules = <PlanNotificationSchedule>[];
  final failReminderIds = <String>{};

  @override
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  }) async {
    if (failReminderIds.contains(reminderId)) {
      throw const NotificationSchedulingFailed();
    }
    reminderIds.add(reminderId);
    reminderDrafts.add(draft);
  }

  @override
  Future<void> cancel({required String reminderId}) async {}

  @override
  Future<void> schedulePlan({
    required String planId,
    required PlanNotificationSchedule schedule,
  }) async {
    planIds.add(planId);
    planSchedules.add(schedule);
  }

  @override
  Future<void> cancelPlan({required String planId}) async {}
}

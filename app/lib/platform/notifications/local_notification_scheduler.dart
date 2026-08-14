import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/reminder_drafts/domain/reminder_draft.dart';
import '../../features/plans/domain/plan_models.dart';
import 'reminder_notification_scheduler.dart';

abstract interface class LocalNotificationGateway {
  Future<bool> requestPermissions();

  Future<void> schedule({
    required int id,
    required String title,
    required tz.TZDateTime scheduledDate,
  });

  Future<void> cancel({required int id});
}

abstract interface class DailyLocalNotificationGateway {
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required tz.TZDateTime firstDate,
  });
}

abstract interface class PlanNotificationScheduler {
  Future<void> schedulePlan({
    required String planId,
    required PlanNotificationSchedule schedule,
  });

  Future<void> cancelPlan({required String planId});
}

class LocalNotificationScheduler
    implements ReminderNotificationScheduler, PlanNotificationScheduler {
  static const _maxDailyPlanNotifications = 8;

  LocalNotificationScheduler({
    required this.gateway,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    tz_data.initializeTimeZones();
  }

  final LocalNotificationGateway gateway;
  final DateTime Function() _now;

  Future<void> initializeGateway() async {
    final gateway = this.gateway;
    if (gateway is FlutterLocalNotificationGateway) {
      await gateway.initialize();
    }
  }

  @override
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  }) async {
    final scheduledAt = draft.scheduledAt;
    if (scheduledAt == null || !scheduledAt.isAfter(_now())) {
      throw const InvalidNotificationSchedule();
    }

    late final tz.Location location;
    try {
      location = tz.getLocation(draft.timezone);
    } catch (_) {
      throw const InvalidNotificationSchedule();
    }
    final scheduledDate = tz.TZDateTime(
      location,
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
      scheduledAt.hour,
      scheduledAt.minute,
      scheduledAt.second,
    );

    late final bool permissionGranted;
    try {
      permissionGranted = await gateway.requestPermissions();
    } catch (_) {
      throw const NotificationSchedulingFailed();
    }
    if (!permissionGranted) {
      throw const NotificationPermissionDenied();
    }
    try {
      await gateway.schedule(
        id: _stableNotificationId(reminderId),
        title: draft.title,
        scheduledDate: scheduledDate,
      );
    } catch (_) {
      throw const NotificationSchedulingFailed();
    }
  }

  @override
  Future<void> cancel({required String reminderId}) async {
    try {
      await gateway.cancel(id: _stableNotificationId(reminderId));
    } catch (_) {
      throw const NotificationCancellationFailed();
    }
  }

  @override
  Future<void> schedulePlan({
    required String planId,
    required PlanNotificationSchedule schedule,
  }) async {
    if (schedule.scheduledTimes.isEmpty ||
        schedule.scheduledTimes.length > _maxDailyPlanNotifications ||
        schedule.scheduledTimes.any((value) => !value.isAfter(_now())) ||
        (schedule.repeat == PlanRepeat.none &&
            schedule.scheduledTimes.length != 1)) {
      throw const InvalidNotificationSchedule();
    }
    final permissionGranted = await gateway.requestPermissions();
    if (!permissionGranted) throw const NotificationPermissionDenied();
    late final tz.Location location;
    try {
      location = tz.getLocation(schedule.timezone);
    } catch (_) {
      throw const InvalidNotificationSchedule();
    }
    final scheduledIds = <int>[];
    try {
      for (var index = 0; index < schedule.scheduledTimes.length; index++) {
        final date =
            tz.TZDateTime.from(schedule.scheduledTimes[index], location);
        final id = _stableNotificationId('plan:$planId:$index');
        if (schedule.repeat == PlanRepeat.daily) {
          final dailyGateway = gateway;
          if (dailyGateway is! DailyLocalNotificationGateway) {
            throw const NotificationSchedulingFailed();
          }
          await (dailyGateway as DailyLocalNotificationGateway).scheduleDaily(
            id: id,
            title: schedule.title,
            firstDate: date,
          );
        } else {
          await gateway.schedule(
            id: id,
            title: schedule.title,
            scheduledDate: date,
          );
        }
        scheduledIds.add(id);
      }
    } catch (_) {
      for (final id in scheduledIds) {
        try {
          await gateway.cancel(id: id);
        } catch (_) {}
      }
      throw const NotificationSchedulingFailed();
    }
  }

  @override
  Future<void> cancelPlan({required String planId}) async {
    var failed = false;
    final ids = <int>[
      _stableNotificationId('plan:$planId'),
      for (var index = 0; index < _maxDailyPlanNotifications; index++)
        _stableNotificationId('plan:$planId:$index'),
    ];
    for (final id in ids) {
      try {
        await gateway.cancel(id: id);
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      throw const NotificationCancellationFailed();
    }
  }

  static int _stableNotificationId(String reminderId) {
    var hash = 0;
    for (final codeUnit in reminderId.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash;
  }
}

class FlutterLocalNotificationGateway
    implements LocalNotificationGateway, DailyLocalNotificationGateway {
  FlutterLocalNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    const settings = InitializationSettings(
      iOS: IOSInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
  }

  @override
  Future<bool> requestPermissions() async {
    return await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required tz.TZDateTime scheduledDate,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: '提醒时间到了',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          threadIdentifier: 'smart-reminder',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'reminder:$id',
    );
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required tz.TZDateTime firstDate,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: '用药时间到了',
      scheduledDate: firstDate,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          threadIdentifier: 'smart-reminder-plans',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'plan:$id',
    );
  }

  @override
  Future<void> cancel({required int id}) async {
    await _plugin.cancel(id: id);
  }
}

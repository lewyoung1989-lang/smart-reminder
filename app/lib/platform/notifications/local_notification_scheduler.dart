import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/reminder_drafts/domain/reminder_draft.dart';
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

class LocalNotificationScheduler implements ReminderNotificationScheduler {
  LocalNotificationScheduler({
    required this.gateway,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    tz_data.initializeTimeZones();
  }

  final LocalNotificationGateway gateway;
  final DateTime Function() _now;

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

  static int _stableNotificationId(String reminderId) {
    var hash = 0;
    for (final codeUnit in reminderId.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash;
  }
}

class FlutterLocalNotificationGateway implements LocalNotificationGateway {
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
  Future<void> cancel({required int id}) async {
    await _plugin.cancel(id: id);
  }
}

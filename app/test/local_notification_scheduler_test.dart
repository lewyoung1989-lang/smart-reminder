import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/platform/notifications/local_notification_scheduler.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';
import 'package:timezone/timezone.dart' as tz;


class RecordingNotificationGateway implements LocalNotificationGateway {
  bool permissionGranted = true;
  int permissionRequestCount = 0;
  final scheduled = <({int id, String title, tz.TZDateTime date})>[];
  final cancelled = <int>[];

  @override
  Future<bool> requestPermissions() async {
    permissionRequestCount += 1;
    return permissionGranted;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required tz.TZDateTime scheduledDate,
  }) async {
    scheduled.add((id: id, title: title, date: scheduledDate));
  }

  Future<void> cancel({required int id}) async {
    cancelled.add(id);
  }
}


void main() {
  final now = DateTime(2026, 8, 4, 10);

  ReminderDraft draftAt(DateTime? date) => ReminderDraft(
        id: 'draft-1',
        title: '喝水',
        scheduledAt: date,
        timezone: 'Asia/Shanghai',
        severity: ReminderSeverity.notification,
        weatherMessage: null,
        ambiguities: const [],
        parserSource: 'local',
      );

  test('requests permission and schedules in the draft timezone', () async {
    final gateway = RecordingNotificationGateway();
    final scheduler = LocalNotificationScheduler(
      gateway: gateway,
      now: () => now,
    );

    await scheduler.schedule(
      reminderId: 'reminder-1',
      draft: draftAt(DateTime(2026, 8, 4, 10, 1)),
    );

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.scheduled.single.title, '喝水');
    expect(gateway.scheduled.single.date.location.name, 'Asia/Shanghai');
    expect(gateway.scheduled.single.date.hour, 10);
    expect(gateway.scheduled.single.date.minute, 1);
  });

  test('permission denial stops scheduling', () async {
    final gateway = RecordingNotificationGateway()..permissionGranted = false;
    final scheduler = LocalNotificationScheduler(gateway: gateway, now: () => now);

    await expectLater(
      scheduler.schedule(
        reminderId: 'reminder-1',
        draft: draftAt(DateTime(2026, 8, 4, 10, 1)),
      ),
      throwsA(isA<NotificationPermissionDenied>()),
    );
    expect(gateway.scheduled, isEmpty);
  });

  test('past or missing time is rejected before asking permission', () async {
    final gateway = RecordingNotificationGateway();
    final scheduler = LocalNotificationScheduler(gateway: gateway, now: () => now);

    await expectLater(
      scheduler.schedule(
        reminderId: 'reminder-1',
        draft: draftAt(DateTime(2026, 8, 4, 9, 59)),
      ),
      throwsA(isA<InvalidNotificationSchedule>()),
    );
    await expectLater(
      scheduler.schedule(reminderId: 'reminder-1', draft: draftAt(null)),
      throwsA(isA<InvalidNotificationSchedule>()),
    );
    expect(gateway.scheduled, isEmpty);
  });

  test('cancels the stable scheduled id without requesting permission', () async {
    final gateway = RecordingNotificationGateway();
    final scheduler = LocalNotificationScheduler(gateway: gateway, now: () => now);

    await scheduler.schedule(
      reminderId: 'reminder-1',
      draft: draftAt(DateTime(2026, 8, 4, 10, 1)),
    );
    await scheduler.cancel(reminderId: 'reminder-1');

    expect(gateway.cancelled.single, gateway.scheduled.single.id);
    expect(gateway.permissionRequestCount, 1);
  });
}

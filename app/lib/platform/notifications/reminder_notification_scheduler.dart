import '../../features/reminder_drafts/domain/reminder_draft.dart';


abstract interface class ReminderNotificationScheduler {
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  });

  Future<void> cancel({required String reminderId});
}


sealed class ReminderNotificationException implements Exception {
  const ReminderNotificationException();
}


class NotificationPermissionDenied extends ReminderNotificationException {
  const NotificationPermissionDenied();
}


class InvalidNotificationSchedule extends ReminderNotificationException {
  const InvalidNotificationSchedule();
}


class NotificationSchedulingFailed extends ReminderNotificationException {
  const NotificationSchedulingFailed();
}


class NotificationCancellationFailed extends ReminderNotificationException {
  const NotificationCancellationFailed();
}

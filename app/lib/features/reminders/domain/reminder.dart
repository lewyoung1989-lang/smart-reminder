enum ReminderStatus { pending, expired, cancelled }

enum ReminderSeverity { alarm, notification }

extension ReminderStatusValue on ReminderStatus {
  String get apiValue => switch (this) {
        ReminderStatus.pending => 'pending',
        ReminderStatus.expired => 'expired',
        ReminderStatus.cancelled => 'cancelled',
      };
}

class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.timezone,
    required this.scheduledAt,
    required this.severity,
    required this.status,
    required this.cancelledAt,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as String,
        title: json['title'] as String,
        timezone: json['timezone'] as String,
        scheduledAt:
            DateTime.parse(json['scheduled_at'] as String).toLocal(),
        severity: json['severity'] == 'alarm'
            ? ReminderSeverity.alarm
            : ReminderSeverity.notification,
        status: switch (json['status']) {
          'expired' => ReminderStatus.expired,
          'cancelled' => ReminderStatus.cancelled,
          _ => ReminderStatus.pending,
        },
        cancelledAt: json['cancelled_at'] == null
            ? null
            : DateTime.parse(json['cancelled_at'] as String).toLocal(),
      );

  final String id;
  final String title;
  final String timezone;
  final DateTime scheduledAt;
  final ReminderSeverity severity;
  final ReminderStatus status;
  final DateTime? cancelledAt;
}

class ReminderPage {
  const ReminderPage({
    required this.reminders,
    required this.nextPage,
  });

  final List<Reminder> reminders;
  final Uri? nextPage;
}

class ReminderCreationResult {
  const ReminderCreationResult({
    required this.reminderId,
    required this.notificationScheduled,
  });

  final String reminderId;
  final bool notificationScheduled;
}

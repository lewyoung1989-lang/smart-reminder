enum PlanStatus { active, pending, paused }

enum PlanKind { medication, departure, reminder }

enum PlanExecutionStatus {
  pending,
  running,
  completed,
  degraded,
  failed,
  cancelled,
}

enum PlanRepeat { none, daily }

class PlanNotificationSchedule {
  const PlanNotificationSchedule({
    required this.scheduledAt,
    required this.repeat,
    required this.title,
    required this.timezone,
  });

  final DateTime scheduledAt;
  final PlanRepeat repeat;
  final String title;
  final String timezone;
}

class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.nextRunAt,
    required this.status,
    required this.kind,
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime nextRunAt;
  final PlanStatus status;
  final PlanKind kind;
}

class PlanExecution {
  const PlanExecution({
    required this.startedAt,
    required this.status,
    required this.message,
  });

  final DateTime startedAt;
  final PlanExecutionStatus status;
  final String message;
}

class PlanDetail {
  PlanDetail({
    required this.summary,
    this.arrivalLabel,
    this.destination,
    required List<String> queriedSources,
    required this.reminderLabel,
    required List<PlanExecution> executions,
    this.isDegraded = false,
    this.degradationMessage,
    this.sourceText = '',
    this.notificationSchedule,
  })  : queriedSources = List.unmodifiable(queriedSources),
        executions = List.unmodifiable(executions);

  final PlanSummary summary;
  final String? arrivalLabel;
  final String? destination;
  final List<String> queriedSources;
  final String reminderLabel;
  final List<PlanExecution> executions;
  final bool isDegraded;
  final String? degradationMessage;
  final String sourceText;
  final PlanNotificationSchedule? notificationSchedule;
}

class PlanCollection {
  PlanCollection({required List<PlanSummary> items, this.isOffline = false})
      : items = List.unmodifiable(items);

  final List<PlanSummary> items;
  final bool isOffline;
}

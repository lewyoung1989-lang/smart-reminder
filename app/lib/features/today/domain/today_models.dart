enum AttentionKind { confirmation, degraded, permission }

enum TimelineStatus { upcoming, due, completed, skipped }

class AttentionItem {
  const AttentionItem({
    required this.id,
    required this.title,
    required this.reason,
    required this.dueAt,
    required this.kind,
    required this.actionLabel,
    this.actionTarget,
  });

  final String id;
  final String title;
  final String reason;
  final DateTime dueAt;
  final AttentionKind kind;
  final String actionLabel;
  final ActionTarget? actionTarget;
}

class ActionTarget {
  const ActionTarget({
    required this.resource,
    required this.id,
  });

  final String resource;
  final String id;
}

class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.scheduledAt,
    required this.status,
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime scheduledAt;
  final TimelineStatus status;
}

class TodaySnapshot {
  TodaySnapshot({
    required List<AttentionItem> decisions,
    required List<TimelineItem> timeline,
    this.isOffline = false,
  })  : decisions = List.unmodifiable(decisions),
        timeline = List.unmodifiable(timeline);

  final List<AttentionItem> decisions;
  final List<TimelineItem> timeline;
  final bool isOffline;
}

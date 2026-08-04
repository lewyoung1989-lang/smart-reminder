enum ReminderSeverity { alarm, notification }


class ReminderDraft {
  const ReminderDraft({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.timezone,
    required this.severity,
    required this.weatherMessage,
    required this.ambiguities,
    required this.parserSource,
  });

  factory ReminderDraft.fromJson(Map<String, dynamic> json) {
    final draft = json['draft'] as Map<String, dynamic>;
    final schedule = draft['schedule'] as Map<String, dynamic>?;
    return ReminderDraft(
      id: json['id'] as String,
      title: draft['title'] as String,
      scheduledAt: schedule == null
          ? null
          : DateTime.parse(schedule['local_datetime'] as String).toLocal(),
      timezone: schedule?['timezone'] as String? ?? 'Asia/Shanghai',
      severity: draft['severity'] == 'alarm'
          ? ReminderSeverity.alarm
          : ReminderSeverity.notification,
      weatherMessage: draft['condition_met_message'] as String?,
      ambiguities: List<String>.from(draft['ambiguities'] as List? ?? const []),
      parserSource: json['parser_source'] as String? ?? 'local',
    );
  }

  final String id;
  final String title;
  final DateTime? scheduledAt;
  final String timezone;
  final ReminderSeverity severity;
  final String? weatherMessage;
  final List<String> ambiguities;
  final String parserSource;

  bool get canConfirm => scheduledAt != null && ambiguities.isEmpty;

  String get parserSourceLabel => switch (parserSource) {
        'deepseek' => 'DeepSeek',
        'local_fallback' => '本地规则（模型不可用）',
        _ => '本地规则',
      };

  String displayTime(DateTime now) {
    final value = scheduledAt;
    if (value == null) return '时间待补充';
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(value.year, value.month, value.day);
    final dayDifference = target.difference(today).inDays;
    final dayLabel = switch (dayDifference) {
      0 => '今天',
      1 => '明天',
      _ => '${value.month}月${value.day}日',
    };
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$dayLabel $hour:$minute';
  }
}

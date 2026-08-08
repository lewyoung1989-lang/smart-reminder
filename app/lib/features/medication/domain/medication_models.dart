enum MedicationOccurrenceStatus { pending, taken, skipped, missed, unknown }

enum MedicationOccurrenceAction { taken, skipped }

class MedicationPlan {
  MedicationPlan({
    required this.id,
    required this.medicineId,
    required this.dosageText,
    required this.timezone,
    required List<String> times,
    required this.enabled,
  }) : times = List.unmodifiable(times);

  factory MedicationPlan.fromJson(Map<String, dynamic> json) => MedicationPlan(
        id: json['id'] as String,
        medicineId: json['medicine_id'] as String,
        dosageText: json['dosage_text'] as String,
        timezone: json['timezone'] as String,
        times: (json['times'] as List<dynamic>).cast<String>(),
        enabled: json['enabled'] as bool,
      );

  final String id;
  final String medicineId;
  final String dosageText;
  final String timezone;
  final List<String> times;
  final bool enabled;
}

class MedicationOccurrence {
  const MedicationOccurrence({
    required this.id,
    required this.planId,
    required this.scheduledAt,
    required this.status,
    required this.actedAt,
  });

  factory MedicationOccurrence.fromJson(Map<String, dynamic> json) {
    return MedicationOccurrence(
      id: json['id'] as String,
      planId: json['plan_id'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      status: _parseStatus(json['status'] as String?),
      actedAt: _parseNullableDateTime(json['acted_at']),
    );
  }

  final String id;
  final String planId;
  final DateTime scheduledAt;
  final MedicationOccurrenceStatus status;
  final DateTime? actedAt;

  static MedicationOccurrenceStatus _parseStatus(String? value) =>
      switch (value) {
        'pending' => MedicationOccurrenceStatus.pending,
        'taken' => MedicationOccurrenceStatus.taken,
        'skipped' => MedicationOccurrenceStatus.skipped,
        'missed' => MedicationOccurrenceStatus.missed,
        _ => MedicationOccurrenceStatus.unknown,
      };

  static DateTime? _parseNullableDateTime(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;
}

String medicationOccurrenceActionValue(MedicationOccurrenceAction action) =>
    switch (action) {
      MedicationOccurrenceAction.taken => 'taken',
      MedicationOccurrenceAction.skipped => 'skipped',
    };

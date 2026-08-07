import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/voice_reminders/domain/reminder_draft.dart';

void main() {
  test('legacy voice draft import supplies the local parser source by default',
      () {
    final draft = ReminderDraft(
      id: 'voice-draft-1',
      title: '喝水',
      scheduledAt: DateTime(2026, 8, 7, 10),
      timezone: 'Asia/Shanghai',
      severity: ReminderSeverity.notification,
      weatherMessage: null,
      ambiguities: const [],
    );

    expect(draft.parserSource, 'local');
  });
}

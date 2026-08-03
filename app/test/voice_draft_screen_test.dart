import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/voice_reminders/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/voice_reminders/presentation/voice_draft_screen.dart';

void main() {
  testWidgets('voice draft requires explicit confirmation', (tester) async {
    final draft = ReminderDraft(
      id: 'draft-1',
      title: '起床并查看天气',
      scheduledAt: DateTime(2026, 8, 4, 7, 30),
      timezone: 'Asia/Shanghai',
      severity: ReminderSeverity.alarm,
      weatherMessage: '未来两小时可能有雨，建议带伞',
      ambiguities: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceDraftScreen(
          transcript: '明天早上七点半叫我起床，先查未来两小时天气，如果下雨提醒我带伞。',
          draft: draft,
          now: DateTime(2026, 8, 3, 10),
          onConfirm: () async {},
        ),
      ),
    );

    expect(find.text('结构化提醒草稿'), findsOneWidget);
    expect(find.text('明天 07:30'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认创建'), findsOneWidget);
  });
}

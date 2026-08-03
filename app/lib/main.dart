import 'package:flutter/material.dart';

import 'features/voice_reminders/domain/reminder_draft.dart';
import 'features/voice_reminders/presentation/voice_draft_screen.dart';


void main() {
  runApp(const SmartReminderApp());
}


class SmartReminderApp extends StatelessWidget {
  const SmartReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final draft = ReminderDraft(
      id: 'local-preview',
      title: '起床并查看天气',
      scheduledAt: DateTime.now().add(const Duration(days: 1)),
      timezone: 'Asia/Shanghai',
      severity: ReminderSeverity.alarm,
      weatherMessage: '未来两小时可能有雨，建议带伞',
      ambiguities: const [],
    );
    return MaterialApp(
      title: '智能生活提醒',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006C4C)),
        useMaterial3: true,
      ),
      home: VoiceDraftScreen(
        transcript: '明天早上七点半叫我起床，先查未来两小时天气，如果下雨提醒我带伞。',
        draft: draft,
        onConfirm: () async {},
      ),
    );
  }
}

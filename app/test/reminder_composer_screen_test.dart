import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/presentation/reminder_composer_screen.dart';


void main() {
  ReminderDraft testDraft({List<String> ambiguities = const []}) {
    return ReminderDraft(
      id: 'draft-1',
      title: '喝水',
      scheduledAt: DateTime(2026, 8, 4, 10, 1),
      timezone: 'Asia/Shanghai',
      severity: ReminderSeverity.notification,
      weatherMessage: null,
      ambiguities: ambiguities,
      parserSource: 'local',
    );
  }

  Widget testApp({
    required Future<ReminderDraft> Function(String) createDraft,
    Future<String> Function(String)? confirmDraft,
  }) {
    return MaterialApp(
      home: ReminderComposerScreen(
        createDraft: createDraft,
        confirmDraft: confirmDraft ?? (_) async => 'reminder-1',
        now: DateTime(2026, 8, 4, 10),
      ),
    );
  }

  testWidgets('text input creates a draft and requires confirmation', (tester) async {
    String? submittedText;
    await tester.pumpWidget(
      testApp(
        createDraft: (text) async {
          submittedText = text;
          return testDraft();
        },
      ),
    );

    await tester.enterText(find.byType(TextField), '1分钟后提醒我喝水');
    await tester.tap(find.widgetWithText(FilledButton, '解析提醒'));
    await tester.pumpAndSettle();

    expect(submittedText, '1分钟后提醒我喝水');
    expect(find.text('提醒草稿'), findsOneWidget);
    expect(find.text('喝水'), findsOneWidget);
    expect(find.text('本地规则'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认创建'), findsOneWidget);
  });

  testWidgets('submit shows a stable loading state', (tester) async {
    final completer = Completer<ReminderDraft>();
    await tester.pumpWidget(
      testApp(createDraft: (_) => completer.future),
    );

    await tester.enterText(find.byType(TextField), '1分钟后提醒我喝水');
    await tester.tap(find.widgetWithText(FilledButton, '解析提醒'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    completer.complete(testDraft());
    await tester.pumpAndSettle();
  });

  testWidgets('API error stays on input and can be retried', (tester) async {
    await tester.pumpWidget(
      testApp(createDraft: (_) async => throw Exception('network')),
    );

    await tester.enterText(find.byType(TextField), '1分钟后提醒我喝水');
    await tester.tap(find.widgetWithText(FilledButton, '解析提醒'));
    await tester.pumpAndSettle();

    expect(find.text('暂时无法解析，请检查网络后重试'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '解析提醒'), findsOneWidget);
  });

  testWidgets('ambiguous draft cannot be confirmed', (tester) async {
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => testDraft(ambiguities: const ['缺少提醒时间']),
      ),
    );

    await tester.enterText(find.byType(TextField), '提醒我喝水');
    await tester.tap(find.widgetWithText(FilledButton, '解析提醒'));
    await tester.pumpAndSettle();

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认创建'),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text('缺少提醒时间'), findsOneWidget);
  });
}

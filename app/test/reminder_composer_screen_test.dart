import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/quick_create/domain/quick_create_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/presentation/reminder_composer_screen.dart';

void main() {
  QuickCreateDraft testDraft({List<String> ambiguities = const []}) {
    return QuickCreateDraft.reminder(
      reminder: ReminderDraft(
        id: 'draft-1',
        title: '喝水',
        scheduledAt: DateTime(2026, 8, 4, 10, 1),
        timezone: 'Asia/Shanghai',
        severity: ReminderSeverity.notification,
        weatherMessage: null,
        ambiguities: ambiguities,
        parserSource: 'local',
      ),
    );
  }

  Widget testApp({
    required Future<QuickCreateDraft> Function(String) createDraft,
    Future<String> Function(String)? confirmDraft,
    Future<String> Function(String)? confirmWorkflowDraft,
    Future<WorkflowDraft> Function(String draftId, String answer)?
        answerWorkflowDraft,
  }) {
    return MaterialApp(
      home: ReminderComposerScreen(
        createDraft: createDraft,
        confirmDraft: confirmDraft ?? (_) async => 'reminder-1',
        confirmWorkflowDraft: confirmWorkflowDraft,
        answerWorkflowDraft: answerWorkflowDraft,
        now: DateTime(2026, 8, 4, 10),
      ),
    );
  }

  testWidgets('text input creates a draft and requires confirmation',
      (tester) async {
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
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(submittedText, '1分钟后提醒我喝水');
    expect(find.text('确认计划'), findsOneWidget);
    expect(find.text('喝水'), findsOneWidget);
    expect(find.text('本地规则'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认'), findsOneWidget);
  });

  testWidgets('submit shows a stable loading state', (tester) async {
    final completer = Completer<QuickCreateDraft>();
    await tester.pumpWidget(
      testApp(createDraft: (_) => completer.future),
    );

    await tester.enterText(find.byType(TextField), '1分钟后提醒我喝水');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pump();

    final progress = find.byType(CircularProgressIndicator);
    expect(progress, findsOneWidget);
    final submittingButton = find.ancestor(
      of: progress,
      matching: find.byType(FilledButton),
    );
    expect(submittingButton, findsOneWidget);
    expect(tester.widget<FilledButton>(submittingButton).onPressed, isNull);

    completer.complete(testDraft());
    await tester.pumpAndSettle();
  });

  testWidgets('API error stays on input and can be retried', (tester) async {
    await tester.pumpWidget(
      testApp(createDraft: (_) async => throw Exception('network')),
    );

    await tester.enterText(find.byType(TextField), '1分钟后提醒我喝水');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(find.text('暂时无法解析，请检查网络后重试'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '继续'), findsOneWidget);
  });

  testWidgets('ambiguous draft cannot be confirmed', (tester) async {
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => testDraft(ambiguities: const ['缺少提醒时间']),
      ),
    );

    await tester.enterText(find.byType(TextField), '提醒我喝水');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认'),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text('缺少提醒时间'), findsOneWidget);
  });

  testWidgets('Modify edits the expression on the confirmation page', (
    tester,
  ) async {
    String? reparseText;
    await tester.pumpWidget(
      testApp(
        createDraft: (text) async {
          reparseText = text;
          return testDraft();
        },
      ),
    );

    await tester.enterText(find.byType(TextField), '明天九点提醒我喝水');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '修改'));
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('reminder-reparse-input'));
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '明天九点提醒我喝水');

    await tester.enterText(input, '明天十点提醒我喝水');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reminder-reparse-submit')));
    await tester.pumpAndSettle();

    expect(reparseText, '明天十点提醒我喝水');
    expect(find.text('确认计划'), findsOneWidget);
    expect(find.text('明天十点提醒我喝水'), findsOneWidget);
  });

  WorkflowDraft workflowDraft({
    List<String> ambiguities = const [],
    String policyDecision = 'needs_confirmation',
  }) {
    return WorkflowDraft(
      id: 'workflow-draft-1',
      title: '提醒草稿',
      templateHint: 'medication_cycle',
      slots: const {
        'medicine_name': '降压药',
        'frequency': 'daily',
        'time_of_day': '09:00',
      },
      ambiguities: ambiguities,
      policyDecision: policyDecision,
      riskLevel: 'R2',
      policyQuestion: null,
    );
  }

  testWidgets('workflow draft with clarification cannot be confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => QuickCreateDraft.workflow(
          workflow: workflowDraft(
            ambiguities: const ['请补充药品剂量和服药周期'],
            policyDecision: 'needs_clarification',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '每天早上9点吃药');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(find.text('周期用药'), findsWidgets);
    expect(find.textContaining('请补充药品剂量和服药周期'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认'),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('confirmable workflow draft confirms through workflow API', (
    tester,
  ) async {
    String? confirmedId;
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => QuickCreateDraft.workflow(
          workflow: workflowDraft(),
        ),
        confirmWorkflowDraft: (id) async {
          confirmedId = id;
          return 'rule-1';
        },
      ),
    );

    await tester.enterText(find.byType(TextField), '每天早上9点吃药');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(find.text('降压药'), findsOneWidget);
    expect(find.text('每天'), findsOneWidget);
    expect(find.text('R2（每次确认）'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(confirmedId, 'workflow-draft-1');
  });

  testWidgets('workflow draft displays all daily medication times', (
    tester,
  ) async {
    final draft = WorkflowDraft(
      id: 'workflow-draft-3-times',
      title: '用药提醒',
      templateHint: 'medication_cycle',
      slots: const {
        'medicine_name': '拜新同',
        'dose_text': '1片',
        'frequency': 'daily',
        'time_of_day': '08:00',
        'times': ['08:00', '13:00', '20:00'],
      },
      ambiguities: const [],
      policyDecision: 'needs_confirmation',
      riskLevel: 'R2',
      policyQuestion: null,
    );
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => QuickCreateDraft.workflow(workflow: draft),
      ),
    );

    await tester.enterText(find.byType(TextField), '每天三次吃拜新同');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(find.text('08:00、13:00、20:00'), findsOneWidget);
  });

  testWidgets('answering a clarification refreshes the workflow draft', (
    tester,
  ) async {
    String? answeredId;
    String? answerText;
    String? confirmedId;
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => QuickCreateDraft.workflow(
          workflow: workflowDraft(
            ambiguities: const ['请补充药品剂量和服药周期'],
            policyDecision: 'needs_clarification',
          ),
        ),
        answerWorkflowDraft: (id, answer) async {
          answeredId = id;
          answerText = answer;
          return workflowDraft();
        },
        confirmWorkflowDraft: (id) async {
          confirmedId = id;
          return 'rule-1';
        },
      ),
    );

    await tester.enterText(find.byType(TextField), '以后每天9点我吃药');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workflow-answer-input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('workflow-answer-input')),
      '吃阿莫西林1片',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('workflow-answer-submit')));
    await tester.pumpAndSettle();

    expect(answeredId, 'workflow-draft-1');
    expect(answerText, '吃阿莫西林1片');
    expect(find.textContaining('请补充药品剂量和服药周期'), findsNothing);
    expect(find.byKey(const Key('workflow-answer-input')), findsNothing);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认'),
    );
    expect(confirm.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(confirmedId, 'workflow-draft-1');
  });
}

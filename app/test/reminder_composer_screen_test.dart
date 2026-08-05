import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/presentation/reminder_composer_screen.dart';
import 'package:smart_reminder_app/features/voice_input/data/voice_transcription_api.dart';
import 'package:smart_reminder_app/features/voice_input/services/voice_input_service.dart';

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
    Future<void> Function()? startRecording,
    Future<String> Function()? stopRecording,
    Future<void> Function()? cancelRecording,
    Duration maxRecordingDuration = const Duration(seconds: 20),
  }) {
    return MaterialApp(
      home: ReminderComposerScreen(
        createDraft: createDraft,
        confirmDraft: confirmDraft ?? (_) async => 'reminder-1',
        startRecording: startRecording,
        stopRecording: stopRecording,
        cancelRecording: cancelRecording,
        maxRecordingDuration: maxRecordingDuration,
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
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

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

  testWidgets('microphone starts recording and disables draft parsing', (
    tester,
  ) async {
    var startCalls = 0;
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => testDraft(),
        startRecording: () async => startCalls += 1,
        stopRecording: () async => '提醒我喝水',
        cancelRecording: () async {},
      ),
    );

    await tester.tap(find.byTooltip('开始语音输入'));
    await tester.pump();

    expect(startCalls, 1);
    expect(find.byTooltip('停止并识别'), findsOneWidget);
    expect(find.byTooltip('取消录音'), findsOneWidget);
    final parseButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '解析提醒'),
    );
    expect(parseButton.onPressed, isNull);
  });

  testWidgets('stop fills editable text without creating a draft',
      (tester) async {
    var draftCalls = 0;
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async {
          draftCalls += 1;
          return testDraft();
        },
        startRecording: () async {},
        stopRecording: () async => '明天早上七点提醒我吃药',
        cancelRecording: () async {},
      ),
    );
    await tester.tap(find.byTooltip('开始语音输入'));
    await tester.pump();

    await tester.tap(find.byTooltip('停止并识别'));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, '明天早上七点提醒我吃药');
    expect(input.enabled, isTrue);
    expect(draftCalls, 0);
    expect(find.byTooltip('开始语音输入'), findsOneWidget);
  });

  testWidgets('cancel returns to idle without transcribing', (tester) async {
    var cancelCalls = 0;
    var stopCalls = 0;
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => testDraft(),
        startRecording: () async {},
        stopRecording: () async {
          stopCalls += 1;
          return '不会使用';
        },
        cancelRecording: () async => cancelCalls += 1,
      ),
    );
    await tester.tap(find.byTooltip('开始语音输入'));
    await tester.pump();

    await tester.tap(find.byTooltip('取消录音'));
    await tester.pumpAndSettle();

    expect(cancelCalls, 1);
    expect(stopCalls, 0);
    expect(find.byTooltip('开始语音输入'), findsOneWidget);
  });

  testWidgets('recording automatically stops at the configured limit', (
    tester,
  ) async {
    var stopCalls = 0;
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => testDraft(),
        startRecording: () async {},
        stopRecording: () async {
          stopCalls += 1;
          return '自动停止结果';
        },
        cancelRecording: () async {},
        maxRecordingDuration: const Duration(seconds: 1),
      ),
    );
    await tester.tap(find.byTooltip('开始语音输入'));
    await tester.pump();

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(stopCalls, 1);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, '自动停止结果');
  });

  testWidgets('permission error keeps text entry available', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      testApp(
        createDraft: (text) async {
          submitted = text;
          return testDraft();
        },
        startRecording: () async => throw const VoiceInputException(
          'microphone_permission_denied',
        ),
        stopRecording: () async => '不会使用',
        cancelRecording: () async {},
      ),
    );

    await tester.tap(find.byTooltip('开始语音输入'));
    await tester.pumpAndSettle();

    expect(find.text('未获得麦克风权限，请在系统设置中开启'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '改用键盘输入');
    await tester.tap(find.widgetWithText(FilledButton, '解析提醒'));
    await tester.pumpAndSettle();
    expect(submitted, '改用键盘输入');
  });

  testWidgets('busy and timeout errors use stable messages', (tester) async {
    var error = const VoiceTranscriptionApiException(429, 'asr_busy');
    await tester.pumpWidget(
      testApp(
        createDraft: (_) async => testDraft(),
        startRecording: () async {},
        stopRecording: () async => throw error,
        cancelRecording: () async {},
      ),
    );
    await tester.tap(find.byTooltip('开始语音输入'));
    await tester.pump();
    await tester.tap(find.byTooltip('停止并识别'));
    await tester.pumpAndSettle();
    expect(find.text('语音识别正忙，请稍后重试'), findsOneWidget);

    error = const VoiceTranscriptionApiException(504, 'asr_timeout');
    await tester.tap(find.byTooltip('开始语音输入'));
    await tester.pump();
    await tester.tap(find.byTooltip('停止并识别'));
    await tester.pumpAndSettle();
    expect(find.text('语音识别超时，请重试'), findsOneWidget);
  });
}

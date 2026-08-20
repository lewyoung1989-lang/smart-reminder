import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/quick_create/domain/quick_create_draft.dart';
import 'package:smart_reminder_app/features/quick_create/domain/quick_create_result.dart';
import 'package:smart_reminder_app/features/quick_create/domain/voice_input_controller.dart';
import 'package:smart_reminder_app/features/quick_create/presentation/quick_create_sheet.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';

void main() {
  final draft = QuickCreateDraft.reminder(
    reminder: ReminderDraft(
      id: 'draft-1',
      title: '喝水',
      scheduledAt: DateTime(2026, 8, 4, 10, 1),
      timezone: 'Asia/Shanghai',
      severity: ReminderSeverity.notification,
      weatherMessage: null,
      ambiguities: const [],
      parserSource: 'local',
    ),
  );

  Widget app(
    Widget child, {
    EdgeInsets viewInsets = EdgeInsets.zero,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(viewInsets: viewInsets, textScaler: textScaler),
        child: Scaffold(resizeToAvoidBottomInset: false, body: child),
      ),
    );
  }

  testWidgets('text stays visible while parsing and returns a typed result', (
    tester,
  ) async {
    final completer = Completer<QuickCreateDraft>();
    QuickCreateResult? result;
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) => completer.future,
          onParsed: (value) => result = value,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('quick-create-input')),
      '1分钟后提醒我喝水',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pump();

    expect(find.text('1分钟后提醒我喝水'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(draft);
    await tester.pumpAndSettle();
    expect(result!.sourceText, '1分钟后提醒我喝水');
    expect(result!.draft, same(draft));
  });

  testWidgets('empty input cannot begin parsing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(QuickCreateSheet(createDraft: (_) async {
        calls += 1;
        return draft;
      })),
    );

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '继续'),
    );
    expect(continueButton.onPressed, isNull);
    expect(calls, 0);
  });

  testWidgets('sheet exposes a 44 point cancel action for abandoning input', (
    tester,
  ) async {
    var cancellations = 0;
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          onCancel: () => cancellations += 1,
        ),
      ),
    );

    final cancel = find.widgetWithText(TextButton, '取消');
    expect(cancel, findsOneWidget);
    expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
    await tester.tap(cancel);
    expect(cancellations, 1);
  });

  testWidgets('canceling an active recording releases the voice controller', (
    tester,
  ) async {
    final voice = _FakeVoiceInputController();
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          voiceInputController: voice,
        ),
        textScaler: const TextScaler.linear(1.3),
      ),
    );

    await tester.tap(find.byKey(const Key('quick-create-voice-action')));
    await tester.pump();
    expect(voice.phase, VoiceInputPhase.recording);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(voice.cancelCalls, 1);
    expect(voice.phase, VoiceInputPhase.idle);
  });

  testWidgets('disposing an active sheet releases the voice controller', (
    tester,
  ) async {
    final voice = _FakeVoiceInputController();
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          voiceInputController: voice,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('quick-create-voice-action')));
    await tester.pump();
    expect(voice.phase, VoiceInputPhase.recording);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(voice.cancelCalls, 1);
    expect(voice.phase, VoiceInputPhase.idle);
  });

  testWidgets('parse errors retain input and allow retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async {
            attempts += 1;
            if (attempts == 1) throw StateError('offline');
            return draft;
          },
        ),
      ),
    );
    await tester.enterText(
        find.byKey(const Key('quick-create-input')), '提醒我喝水');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(find.text('暂时无法解析，请检查网络后重试'), findsOneWidget);
    expect(find.text('提醒我喝水'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('sheet applies keyboard inset as bottom padding', (tester) async {
    await tester.pumpWidget(
      app(
        QuickCreateSheet(createDraft: (_) async => draft),
        viewInsets: const EdgeInsets.only(bottom: 240),
      ),
    );

    final padding =
        tester.widget<AnimatedPadding>(find.byType(AnimatedPadding));
    expect(padding.padding, const EdgeInsets.only(bottom: 240));
  });

  testWidgets('voice action reports unavailable without faking recording', (
    tester,
  ) async {
    await tester
        .pumpWidget(app(QuickCreateSheet(createDraft: (_) async => draft)));
    await tester.tap(find.byKey(const Key('quick-create-voice-action')));
    await tester.pump();

    expect(find.text('语音输入暂不可用'), findsOneWidget);
    expect(find.text('停止录音'), findsNothing);
  });

  testWidgets('voice transcript is shown before automatic parsing', (
    tester,
  ) async {
    final voice = _FakeVoiceInputController();
    var parseCalls = 0;
    String? parsedText;
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (text) async {
            parseCalls += 1;
            parsedText = text;
            return draft;
          },
          voiceInputController: voice,
        ),
      ),
    );

    expect(find.bySemanticsLabel('语音输入'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-create-voice-action')));
    await tester.pump();
    expect(voice.phase, VoiceInputPhase.recording);
    expect(find.textContaining('正在录音'), findsOneWidget);
    expect(find.text('说完后点下方“结束并识别”'), findsOneWidget);
    expect(find.text('结束并识别 00:03'), findsOneWidget);

    voice.setPhase(VoiceInputPhase.transcribing);
    await tester.pump();
    expect(find.text('正在转写'), findsOneWidget);

    voice.setFailure('麦克风不可用');
    await tester.pump();
    expect(find.text('麦克风不可用'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(voice.phase, VoiceInputPhase.idle);

    voice.transcript = '明天提醒我喝水';
    await tester.tap(find.byKey(const Key('quick-create-voice-action')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-create-voice-action')));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '明天提醒我喝水',
    );
    expect(parseCalls, 1);
    expect(parsedText, '明天提醒我喝水');
  });

  testWidgets('voice phases preserve panel size and available actions', (
    tester,
  ) async {
    final voice = _FakeVoiceInputController();
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          voiceInputController: voice,
        ),
      ),
    );

    final panel = find.byKey(const Key('quick-create-panel'));
    final voiceAction = find.byKey(const Key('quick-create-voice-action'));
    final voiceActionButton =
        find.byKey(const Key('quick-create-voice-action'));
    final continueAction = find.widgetWithText(FilledButton, '继续');
    final idleHeight = tester.getSize(panel).height;
    expect(tester.getSize(voiceActionButton).height, greaterThanOrEqualTo(44));
    expect(find.text('语音输入'), findsWidgets);
    expect(tester.widget<FilledButton>(continueAction).onPressed, isNull);

    await tester.tap(voiceAction);
    await tester.pump();
    expect(tester.getSize(panel).height, idleHeight);
    expect(voice.phase, VoiceInputPhase.recording);
    expect(find.text('结束并识别 00:03'), findsOneWidget);
    expect(
        find.byKey(const Key('quick-create-recording-status')), findsOneWidget);

    voice.setPhase(VoiceInputPhase.transcribing);
    await tester.pump();
    expect(tester.getSize(panel).height, idleHeight);
    expect(tester.getSize(voiceActionButton).height, greaterThanOrEqualTo(44));
    expect(tester.widget<FilledButton>(continueAction).onPressed, isNull);

    voice.setFailure('麦克风不可用');
    await tester.pump();
    expect(tester.getSize(panel).height, idleHeight);
    final retryAction = find.widgetWithText(TextButton, '重试');
    expect(tester.widget<TextButton>(retryAction).onPressed, isNotNull);
    expect(tester.getSize(retryAction).height, greaterThanOrEqualTo(44));

    await tester.tap(retryAction);
    await tester.pump();
    expect(voice.phase, VoiceInputPhase.idle);
    expect(tester.getSize(panel).height, idleHeight);

    voice.transcript = '明天提醒我喝水';
    await tester.tap(voiceAction);
    await tester.pump();
    await tester.tap(voiceAction);
    await tester.pump();
    expect(tester.getSize(panel).height, idleHeight);
    expect(tester.widget<FilledButton>(continueAction).onPressed, isNotNull);
  });

  testWidgets('rapid voice taps invoke each delayed action once',
      (tester) async {
    final startCompleter = Completer<void>();
    final stopCompleter = Completer<String?>();
    final voice = _DelayedVoiceInputController(
      startCompleter: startCompleter,
      stopCompleter: stopCompleter,
    );
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          voiceInputController: voice,
        ),
      ),
    );

    final voiceAction = find.byKey(const Key('quick-create-voice-action'));
    await tester.tap(voiceAction);
    await tester.tap(voiceAction);
    await tester.pump();
    expect(voice.startCalls, 1);

    startCompleter.complete();
    await tester.pumpAndSettle();
    expect(voice.phase, VoiceInputPhase.recording);

    await tester.tap(voiceAction);
    await tester.tap(voiceAction);
    await tester.pump();
    expect(voice.stopCalls, 1);

    stopCompleter.complete('明天提醒我喝水');
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '明天提醒我喝水',
    );
  });

  testWidgets('voice action errors show retry UI without escaping the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          voiceInputController: _ThrowingVoiceInputController(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('quick-create-voice-action')));
    await tester.pumpAndSettle();

    expect(find.text('语音输入失败，请重试'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
  });

  testWidgets('voice failure status fits without a render overflow', (
    tester,
  ) async {
    final voice = _FakeVoiceInputController();
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          voiceInputController: voice,
        ),
      ),
    );

    voice.setFailure('语音服务暂不可用，请稍后重试');
    await tester.pump();

    expect(find.text('语音服务暂不可用，请稍后重试'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed transcript does not overwrite a manual edit', (
    tester,
  ) async {
    final startCompleter = Completer<void>();
    final stopCompleter = Completer<String?>();
    final voice = _DelayedVoiceInputController(
      startCompleter: startCompleter,
      stopCompleter: stopCompleter,
    );
    await tester.pumpWidget(
      app(
        QuickCreateSheet(
          createDraft: (_) async => draft,
          voiceInputController: voice,
        ),
      ),
    );

    final voiceAction = find.byKey(const Key('quick-create-voice-action'));
    final input = find.byKey(const Key('quick-create-input'));
    await tester.tap(voiceAction);
    await tester.pump();
    startCompleter.complete();
    await tester.pumpAndSettle();
    await tester.tap(voiceAction);
    await tester.pump();

    await tester.enterText(input, '手动修改后的提醒');
    await tester.pump();
    stopCompleter.complete('语音转写结果');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(input).controller!.text,
      '手动修改后的提醒',
    );
    expect(voice.stopCalls, 1);
  });

  testWidgets(
      'sheet scrolls in short landscape with keyboard at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app(
        QuickCreateSheet(createDraft: (_) async => draft),
        viewInsets: const EdgeInsets.only(bottom: 180),
        textScaler: const TextScaler.linear(2),
      ),
    );

    final scrollable = find.byType(SingleChildScrollView);
    expect(scrollable, findsOneWidget);
    final input = find.byKey(const Key('quick-create-input'));
    final beforeScroll = tester.getRect(input).top;
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(tester.getRect(input).top, lessThan(beforeScroll));
    expect(find.bySemanticsLabel('语音输入'), findsOneWidget);
  });
}

class _FakeVoiceInputController extends VoiceInputController {
  VoiceInputPhase _phase = VoiceInputPhase.idle;
  String? _errorMessage;
  String? transcript;
  var cancelCalls = 0;

  @override
  VoiceInputPhase get phase => _phase;

  @override
  Duration get elapsed => const Duration(seconds: 3);

  @override
  String? get errorMessage => _errorMessage;

  void setPhase(VoiceInputPhase value) {
    _phase = value;
    _errorMessage = null;
    notifyListeners();
  }

  void setFailure(String message) {
    _phase = VoiceInputPhase.failure;
    _errorMessage = message;
    notifyListeners();
  }

  @override
  Future<void> start() async => setPhase(VoiceInputPhase.recording);

  @override
  Future<String?> stopAndTranscribe() async {
    setPhase(VoiceInputPhase.transcribing);
    setPhase(VoiceInputPhase.idle);
    return transcript;
  }

  @override
  Future<void> retry() async => setPhase(VoiceInputPhase.idle);

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    setPhase(VoiceInputPhase.idle);
  }
}

class _DelayedVoiceInputController extends VoiceInputController {
  _DelayedVoiceInputController({
    required this.startCompleter,
    required this.stopCompleter,
  });

  final Completer<void> startCompleter;
  final Completer<String?> stopCompleter;
  var startCalls = 0;
  var stopCalls = 0;
  VoiceInputPhase _phase = VoiceInputPhase.idle;

  @override
  VoiceInputPhase get phase => _phase;

  @override
  Duration get elapsed => Duration.zero;

  @override
  String? get errorMessage => null;

  @override
  Future<void> start() async {
    startCalls += 1;
    await startCompleter.future;
    _phase = VoiceInputPhase.recording;
    notifyListeners();
  }

  @override
  Future<String?> stopAndTranscribe() async {
    stopCalls += 1;
    _phase = VoiceInputPhase.transcribing;
    notifyListeners();
    final transcript = await stopCompleter.future;
    _phase = VoiceInputPhase.idle;
    notifyListeners();
    return transcript;
  }

  @override
  Future<void> retry() async {
    _phase = VoiceInputPhase.idle;
    notifyListeners();
  }
}

class _ThrowingVoiceInputController extends VoiceInputController {
  @override
  VoiceInputPhase get phase => VoiceInputPhase.idle;

  @override
  Duration get elapsed => Duration.zero;

  @override
  String? get errorMessage => null;

  @override
  Future<void> start() => Future<void>.error(StateError('microphone failed'));

  @override
  Future<String?> stopAndTranscribe() async => null;

  @override
  Future<void> retry() async {}
}

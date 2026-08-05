import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:smart_reminder_app/features/voice_input/data/audio_recorder_gateway.dart';
import 'package:smart_reminder_app/features/voice_input/domain/voice_transcription.dart';
import 'package:smart_reminder_app/features/voice_input/services/voice_input_service.dart';

class FakeRecorder implements AudioRecorderGateway {
  FakeRecorder({this.permissionGranted = true, this.startGate});

  bool permissionGranted;
  final Completer<void>? startGate;
  RecordConfig? config;
  String? startedPath;
  bool cancelled = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.config = config;
    startedPath = path;
    await File(path).writeAsBytes([1, 2, 3]);
    await startGate?.future;
  }

  @override
  Future<String?> stop() async => startedPath;

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

const transcription = VoiceTranscription(
  requestId: 'request-1',
  transcript: '明天提醒我吃药',
  audioDurationMs: 500,
  transcriptionLatencyMs: 123,
  provider: 'funasr',
);

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('voice-service-');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  VoiceInputService service({
    required FakeRecorder recorder,
    Future<VoiceTranscription> Function(String)? transcribe,
  }) {
    return VoiceInputService(
      recorder: recorder,
      transcribe: transcribe ?? (_) async => transcription,
      temporaryDirectory: () async => tempDirectory,
    );
  }

  test('rejects denied microphone permission without recording', () async {
    final recorder = FakeRecorder(permissionGranted: false);
    final voice = service(recorder: recorder);

    expect(
      voice.start,
      throwsA(
        isA<VoiceInputException>().having(
          (error) => error.code,
          'code',
          'microphone_permission_denied',
        ),
      ),
    );
    expect(recorder.startedPath, isNull);
  });

  test('requests PCM WAV at 16 kHz mono', () async {
    final recorder = FakeRecorder();
    final voice = service(recorder: recorder);

    await voice.start();

    expect(recorder.config?.encoder, AudioEncoder.wav);
    expect(recorder.config?.sampleRate, 16000);
    expect(recorder.config?.numChannels, 1);
    expect(recorder.startedPath, endsWith('.wav'));
    expect(recorder.startedPath, startsWith(tempDirectory.path));
  });

  test('stops, uploads, and deletes local audio after success', () async {
    final recorder = FakeRecorder();
    String? uploadedPath;
    final voice = service(
      recorder: recorder,
      transcribe: (path) async {
        uploadedPath = path;
        expect(await File(path).exists(), isTrue);
        return transcription;
      },
    );
    await voice.start();

    final result = await voice.stopAndTranscribe();

    expect(result, transcription);
    expect(uploadedPath, recorder.startedPath);
    expect(await File(uploadedPath!).exists(), isFalse);
  });

  test('deletes local audio when transcription fails', () async {
    final recorder = FakeRecorder();
    final voice = service(
      recorder: recorder,
      transcribe: (_) async => throw StateError('offline'),
    );
    await voice.start();
    final path = recorder.startedPath!;

    await expectLater(voice.stopAndTranscribe(), throwsStateError);

    expect(await File(path).exists(), isFalse);
  });

  test('cancel discards recording without upload', () async {
    final recorder = FakeRecorder();
    var uploadCalls = 0;
    final voice = service(
      recorder: recorder,
      transcribe: (_) async {
        uploadCalls += 1;
        return transcription;
      },
    );
    await voice.start();
    final path = recorder.startedPath!;

    await voice.cancel();

    expect(recorder.cancelled, isTrue);
    expect(uploadCalls, 0);
    expect(await File(path).exists(), isFalse);
  });

  test('dispose cancels active recording, cleans up, and disposes recorder',
      () async {
    final recorder = FakeRecorder();
    final voice = service(recorder: recorder);
    await voice.start();
    final path = recorder.startedPath!;

    await voice.dispose();

    expect(recorder.cancelled, isTrue);
    expect(recorder.disposed, isTrue);
    expect(await File(path).exists(), isFalse);
  });

  test('dispose during start cancels and deletes the reserved file', () async {
    final gate = Completer<void>();
    final recorder = FakeRecorder(startGate: gate);
    final voice = service(recorder: recorder);

    final starting = voice.start();
    while (recorder.startedPath == null) {
      await Future<void>.delayed(Duration.zero);
    }
    final path = recorder.startedPath!;
    final disposing = voice.dispose();
    gate.complete();

    await expectLater(
      starting,
      throwsA(
        isA<VoiceInputException>().having(
          (error) => error.code,
          'code',
          'service_disposed',
        ),
      ),
    );
    await disposing;

    expect(recorder.cancelled, isTrue);
    expect(recorder.disposed, isTrue);
    expect(await File(path).exists(), isFalse);
  });
}

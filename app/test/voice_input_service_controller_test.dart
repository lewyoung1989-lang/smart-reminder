import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/quick_create/domain/voice_input_controller.dart';
import 'package:smart_reminder_app/features/voice_input/domain/voice_transcription.dart';
import 'package:smart_reminder_app/features/voice_input/services/voice_input_service_controller.dart';

void main() {
  test('records, transcribes and returns to an editable idle state', () async {
    var starts = 0;
    final controller = VoiceInputServiceController(
      startRecording: () async => starts += 1,
      stopAndTranscribe: () async => const VoiceTranscription(
        requestId: 'request-1',
        transcript: '明天早上提醒我吃药',
        audioDurationMs: 800,
        transcriptionLatencyMs: 120,
        provider: 'funasr',
      ),
      cancelRecording: () async {},
    );

    await controller.start();
    expect(starts, 1);
    expect(controller.phase, VoiceInputPhase.recording);

    final transcript = await controller.stopAndTranscribe();
    expect(transcript, '明天早上提醒我吃药');
    expect(controller.phase, VoiceInputPhase.idle);
    expect(controller.errorMessage, isNull);
  });

  test(
      'exposes a stable message after transcription failure and resets on retry',
      () async {
    final controller = VoiceInputServiceController(
      startRecording: () async {},
      stopAndTranscribe: () async => throw const VoiceInputControllerException(
        'asr_busy',
      ),
      cancelRecording: () async {},
    );

    await controller.start();
    await expectLater(controller.stopAndTranscribe(), throwsA(isA<Object>()));
    expect(controller.phase, VoiceInputPhase.failure);
    expect(controller.errorMessage, '语音识别正忙，请稍后重试');

    await controller.retry();
    expect(controller.phase, VoiceInputPhase.idle);
    expect(controller.errorMessage, isNull);
  });

  test('explains audio duration validation failures', () async {
    final controller = VoiceInputServiceController(
      startRecording: () async {},
      stopAndTranscribe: () async => throw const VoiceInputControllerException(
        'audio_too_long',
      ),
      cancelRecording: () async {},
    );

    await controller.start();
    await expectLater(controller.stopAndTranscribe(), throwsA(isA<Object>()));

    expect(controller.phase, VoiceInputPhase.failure);
    expect(controller.errorMessage, '录音超过1分钟，请缩短后重试');
  });
}

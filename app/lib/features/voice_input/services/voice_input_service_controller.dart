import 'dart:async';

import '../../quick_create/domain/voice_input_controller.dart';
import '../data/voice_transcription_api.dart';
import '../domain/voice_transcription.dart';
import 'voice_input_service.dart';

typedef StartRecording = Future<void> Function();
typedef StopAndTranscribe = Future<VoiceTranscription> Function();
typedef CancelRecording = Future<void> Function();

class VoiceInputControllerException implements Exception {
  const VoiceInputControllerException(this.code);

  final String code;
}

class VoiceInputServiceController extends VoiceInputController {
  VoiceInputServiceController({
    required StartRecording startRecording,
    required StopAndTranscribe stopAndTranscribe,
    required CancelRecording cancelRecording,
  })  : _startRecording = startRecording,
        _stopAndTranscribe = stopAndTranscribe,
        _cancelRecording = cancelRecording;

  final StartRecording _startRecording;
  final StopAndTranscribe _stopAndTranscribe;
  final CancelRecording _cancelRecording;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  VoiceInputPhase _phase = VoiceInputPhase.idle;
  String? _errorMessage;

  @override
  VoiceInputPhase get phase => _phase;

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> start() async {
    if (_phase != VoiceInputPhase.idle) return;
    _errorMessage = null;
    notifyListeners();
    try {
      await _startRecording();
      _phase = VoiceInputPhase.recording;
      _stopwatch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        notifyListeners();
      });
      notifyListeners();
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  @override
  Future<String?> stopAndTranscribe() async {
    if (_phase != VoiceInputPhase.recording) return null;
    _stopTimer();
    _phase = VoiceInputPhase.transcribing;
    _errorMessage = null;
    notifyListeners();
    try {
      final transcription = await _stopAndTranscribe();
      _phase = VoiceInputPhase.idle;
      notifyListeners();
      return transcription.transcript;
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  @override
  Future<void> retry() async {
    _stopTimer();
    _phase = VoiceInputPhase.idle;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    if (_phase != VoiceInputPhase.recording) return;
    _stopTimer();
    try {
      await _cancelRecording();
      _phase = VoiceInputPhase.idle;
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch
      ..stop()
      ..reset();
  }

  void _fail(Object error) {
    _stopTimer();
    _phase = VoiceInputPhase.failure;
    _errorMessage = switch (error) {
      VoiceInputControllerException exception => _messageFor(exception.code),
      VoiceInputException exception => _messageFor(exception.code),
      VoiceTranscriptionApiException exception => _messageFor(exception.code),
      _ => '语音识别失败，请重试',
    };
    notifyListeners();
  }

  String _messageFor(String code) => switch (code) {
        'microphone_permission_denied' => '未获得麦克风权限，请在系统设置中开启',
        'asr_busy' || 'rate_limited' => '语音识别正忙，请稍后重试',
        'asr_timeout' => '语音识别超时，请重试',
        'asr_unavailable' => '语音识别暂不可用，请稍后重试',
        'empty_transcript' => '没有听清，请重新录制',
        'audio_too_short' => '录音太短，请重新录制',
        'audio_too_long' => '录音超过1分钟，请缩短后重试',
        'audio_too_large' => '录音文件过大，请缩短后重试',
        'microphone_audio_invalid' => '录音无效，请重新录制',
        _ => '语音识别失败，请重试',
      };
}

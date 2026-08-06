import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../data/audio_recorder_gateway.dart';
import '../domain/voice_transcription.dart';

typedef TranscribeAudio = Future<VoiceTranscription> Function(String audioPath);
typedef TemporaryDirectoryProvider = Future<Directory> Function();

class VoiceInputException implements Exception {
  const VoiceInputException(this.code);

  final String code;

  @override
  String toString() => 'VoiceInputException($code)';
}

class VoiceInputService {
  VoiceInputService({
    required this.recorder,
    required this.transcribe,
    TemporaryDirectoryProvider? temporaryDirectory,
  }) : temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final AudioRecorderGateway recorder;
  final TranscribeAudio transcribe;
  final TemporaryDirectoryProvider temporaryDirectory;
  final Random _random = Random.secure();

  Future<void> _operationTail = Future.value();
  Future<void>? _disposeFuture;
  bool _disposeRequested = false;
  String? _recordingPath;

  Future<void> start() {
    _throwIfDisposing();
    return _runExclusive(_start);
  }

  Future<void> _start() async {
    if (_recordingPath != null) {
      throw const VoiceInputException('recording_in_progress');
    }
    if (!await recorder.hasPermission()) {
      throw const VoiceInputException('microphone_permission_denied');
    }
    _throwIfDisposing();

    final directory = await temporaryDirectory();
    _throwIfDisposing();
    final path = '${directory.path}/voice-'
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(1 << 32)}.wav';
    _recordingPath = path;
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (_disposeRequested) {
        await _cancelActiveRecording();
        throw const VoiceInputException('service_disposed');
      }
    } catch (_) {
      if (_recordingPath == path) _recordingPath = null;
      await _deleteIfPresent(path);
      rethrow;
    }
  }

  Future<VoiceTranscription> stopAndTranscribe() {
    _throwIfDisposing();
    return _runExclusive(_stopAndTranscribe);
  }

  Future<VoiceTranscription> _stopAndTranscribe() async {
    final plannedPath = _recordingPath;
    if (plannedPath == null) {
      throw const VoiceInputException('recording_not_started');
    }

    String? actualPath;
    try {
      actualPath = await recorder.stop();
      return await transcribe(actualPath ?? plannedPath);
    } finally {
      _recordingPath = null;
      await _deleteIfPresent(plannedPath);
      if (actualPath != null && actualPath != plannedPath) {
        await _deleteIfPresent(actualPath);
      }
    }
  }

  Future<void> cancel() {
    _throwIfDisposing();
    return _runExclusive(_cancelActiveRecording);
  }

  Future<void> _cancelActiveRecording() async {
    final path = _recordingPath;
    if (path == null) return;
    _recordingPath = null;
    try {
      await recorder.cancel();
    } finally {
      await _deleteIfPresent(path);
    }
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposeRequested = true;
    final disposing = _runExclusive(() async {
      try {
        await _cancelActiveRecording();
      } finally {
        await recorder.dispose();
      }
    });
    _disposeFuture = disposing;
    return disposing;
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  void _throwIfDisposing() {
    if (_disposeRequested) {
      throw const VoiceInputException('service_disposed');
    }
  }

  Future<void> _deleteIfPresent(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

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

  String? _recordingPath;

  Future<void> start() async {
    if (_recordingPath != null) {
      throw const VoiceInputException('recording_in_progress');
    }
    if (!await recorder.hasPermission()) {
      throw const VoiceInputException('microphone_permission_denied');
    }

    final directory = await temporaryDirectory();
    final path = '${directory.path}/voice-'
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(1 << 32)}.wav';
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _recordingPath = path;
    } catch (_) {
      await _deleteIfPresent(path);
      rethrow;
    }
  }

  Future<VoiceTranscription> stopAndTranscribe() async {
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

  Future<void> cancel() async {
    final path = _recordingPath;
    if (path == null) return;
    _recordingPath = null;
    try {
      await recorder.cancel();
    } finally {
      await _deleteIfPresent(path);
    }
  }

  Future<void> dispose() async {
    try {
      await cancel();
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _deleteIfPresent(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

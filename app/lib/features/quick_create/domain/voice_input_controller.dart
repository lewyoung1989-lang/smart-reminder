import 'package:flutter/foundation.dart';

enum VoiceInputPhase { idle, recording, transcribing, failure }

abstract class VoiceInputController extends ChangeNotifier {
  VoiceInputPhase get phase;
  Duration get elapsed;
  String? get errorMessage;

  Future<void> start();
  Future<String?> stopAndTranscribe();
  Future<void> retry();

  Future<void> cancel() async {}
}

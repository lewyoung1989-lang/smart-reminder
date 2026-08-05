import 'dart:async';

import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'features/reminder_drafts/data/reminder_draft_api.dart';
import 'features/reminder_drafts/presentation/reminder_composer_screen.dart';
import 'features/voice_input/data/audio_recorder_gateway.dart';
import 'features/voice_input/data/voice_transcription_api.dart';
import 'features/voice_input/services/voice_input_service.dart';
import 'platform/notifications/local_notification_scheduler.dart';
import 'platform/notifications/reminder_notification_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationGateway = FlutterLocalNotificationGateway();
  await notificationGateway.initialize();
  runApp(
    SmartReminderApp(
      config: AppConfig.fromEnvironment(),
      notificationScheduler: LocalNotificationScheduler(
        gateway: notificationGateway,
      ),
    ),
  );
}

class SmartReminderApp extends StatefulWidget {
  const SmartReminderApp({
    required this.config,
    required this.notificationScheduler,
    super.key,
  });

  final AppConfig config;
  final ReminderNotificationScheduler notificationScheduler;

  @override
  State<SmartReminderApp> createState() => _SmartReminderAppState();
}

class _SmartReminderAppState extends State<SmartReminderApp> {
  late final ReminderDraftApi _api;
  late final VoiceTranscriptionApi _voiceApi;
  late final VoiceInputService _voiceInput;

  @override
  void initState() {
    super.initState();
    _api = ReminderDraftApi(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.config.apiAccessToken,
    );
    _voiceApi = VoiceTranscriptionApi(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.config.apiAccessToken,
    );
    _voiceInput = VoiceInputService(
      recorder: RecordAudioRecorderGateway(),
      transcribe: _voiceApi.transcribe,
    );
  }

  @override
  void dispose() {
    unawaited(_voiceInput.dispose());
    _voiceApi.close();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智能提醒',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166B5A),
          surface: const Color(0xFFF7F9F8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: ReminderComposerScreen(
        createDraft: _api.createDraft,
        confirmDraft: _api.confirmDraft,
        startRecording: _voiceInput.start,
        stopRecording: () async {
          final result = await _voiceInput.stopAndTranscribe();
          return result.transcript;
        },
        cancelRecording: _voiceInput.cancel,
        notificationScheduler: widget.notificationScheduler,
      ),
    );
  }
}

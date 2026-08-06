import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/notifications/reminder_notification_scheduler.dart';
import '../../reminders/domain/reminder.dart' show ReminderCreationResult;
import '../../voice_input/data/voice_transcription_api.dart';
import '../../voice_input/services/voice_input_service.dart';
import '../domain/reminder_draft.dart';
import 'reminder_draft_screen.dart';

enum _VoiceInputState { idle, starting, recording, transcribing, cancelling }

class ReminderComposerScreen extends StatefulWidget {
  const ReminderComposerScreen({
    required this.createDraft,
    required this.confirmDraft,
    this.notificationScheduler,
    this.startRecording,
    this.stopRecording,
    this.cancelRecording,
    this.maxRecordingDuration = const Duration(seconds: 20),
    this.now,
    super.key,
  });

  final Future<ReminderDraft> Function(String) createDraft;
  final Future<String> Function(String) confirmDraft;
  final ReminderNotificationScheduler? notificationScheduler;
  final Future<void> Function()? startRecording;
  final Future<String> Function()? stopRecording;
  final Future<void> Function()? cancelRecording;
  final Duration maxRecordingDuration;
  final DateTime? now;

  @override
  State<ReminderComposerScreen> createState() => _ReminderComposerScreenState();
}

class _ReminderComposerScreenState extends State<ReminderComposerScreen> {
  final _controller = TextEditingController();
  ReminderDraft? _draft;
  String? _sourceText;
  String? _error;
  bool _isParsing = false;
  String? _confirmedReminderId;
  _VoiceInputState _voiceState = _VoiceInputState.idle;
  Timer? _recordingTimer;

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isParsing || _voiceState != _VoiceInputState.idle) {
      return;
    }
    setState(() {
      _isParsing = true;
      _error = null;
    });
    try {
      final draft = await widget.createDraft(text);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _sourceText = text;
        _confirmedReminderId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '暂时无法解析，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null) return;
    try {
      final reminderId =
          _confirmedReminderId ?? await widget.confirmDraft(draft.id);
      _confirmedReminderId = reminderId;
      final scheduler = widget.notificationScheduler;
      if (scheduler != null) {
        await scheduler.schedule(reminderId: reminderId, draft: draft);
      }
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(
          ReminderCreationResult(
            reminderId: reminderId,
            notificationScheduled: scheduler != null,
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scheduler == null ? '提醒已创建' : '提醒已创建，通知已安排',
          ),
        ),
      );
    } on ReminderNotificationException {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(
          ReminderCreationResult(
            reminderId: _confirmedReminderId!,
            notificationScheduled: false,
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒已创建，但手机通知未安排')),
      );
    } catch (_) {
      if (!mounted) return;
      final reminderId = _confirmedReminderId;
      if (reminderId != null) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(
            ReminderCreationResult(
              reminderId: reminderId,
              notificationScheduled: false,
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提醒已创建，但手机通知未安排')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败，请稍后重试')),
      );
    }
  }

  void _edit() {
    setState(() {
      _draft = null;
      _error = null;
      _confirmedReminderId = null;
    });
  }

  Future<void> _startRecording() async {
    final startRecording = widget.startRecording;
    if (startRecording == null || _voiceState != _VoiceInputState.idle) return;
    setState(() {
      _voiceState = _VoiceInputState.starting;
      _error = null;
    });
    try {
      await startRecording();
      if (!mounted) return;
      setState(() => _voiceState = _VoiceInputState.recording);
      _recordingTimer = Timer(
        widget.maxRecordingDuration,
        () => unawaited(_stopRecording()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceState = _VoiceInputState.idle;
        _error = _voiceErrorMessage(error);
      });
    }
  }

  Future<void> _stopRecording() async {
    final stopRecording = widget.stopRecording;
    if (stopRecording == null || _voiceState != _VoiceInputState.recording) {
      return;
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() {
      _voiceState = _VoiceInputState.transcribing;
      _error = null;
    });
    try {
      final transcript = (await stopRecording()).trim();
      if (!mounted) return;
      setState(() {
        _controller.text = transcript;
        _controller.selection = TextSelection.collapsed(
          offset: transcript.length,
        );
        _voiceState = _VoiceInputState.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceState = _VoiceInputState.idle;
        _error = _voiceErrorMessage(error);
      });
    }
  }

  Future<void> _cancelRecording() async {
    final cancelRecording = widget.cancelRecording;
    if (cancelRecording == null || _voiceState != _VoiceInputState.recording) {
      return;
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() => _voiceState = _VoiceInputState.cancelling);
    try {
      await cancelRecording();
      if (!mounted) return;
      setState(() => _voiceState = _VoiceInputState.idle);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceState = _VoiceInputState.idle;
        _error = _voiceErrorMessage(error);
      });
    }
  }

  String _voiceErrorMessage(Object error) {
    final code = switch (error) {
      VoiceInputException exception => exception.code,
      VoiceTranscriptionApiException exception => exception.code,
      _ => 'unknown_error',
    };
    return switch (code) {
      'microphone_permission_denied' => '未获得麦克风权限，请在系统设置中开启',
      'asr_busy' || 'rate_limited' => '语音识别正忙，请稍后重试',
      'asr_timeout' => '语音识别超时，请重试',
      'asr_unavailable' => '语音识别暂不可用，请稍后重试',
      'empty_transcript' => '没有听清，请重新录制',
      'microphone_audio_invalid' ||
      'audio_too_short' ||
      'audio_too_long' ||
      'audio_too_large' =>
        '录音无效，请重新录制',
      _ => '语音识别失败，请重试',
    };
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft != null) {
      return ReminderDraftScreen(
        sourceText: _sourceText ?? '',
        draft: draft,
        onConfirm: _confirm,
        onEdit: _edit,
        now: widget.now,
      );
    }

    final theme = Theme.of(context);
    final voiceConfigured = widget.startRecording != null &&
        widget.stopRecording != null &&
        widget.cancelRecording != null;
    final isRecording = _voiceState == _VoiceInputState.recording;
    final voiceBusy = _voiceState != _VoiceInputState.idle;
    return Scaffold(
      appBar: AppBar(title: const Text('智能提醒')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _controller,
            enabled: !_isParsing &&
                _voiceState != _VoiceInputState.starting &&
                _voiceState != _VoiceInputState.transcribing &&
                _voiceState != _VoiceInputState.cancelling,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _parse(),
            decoration: const InputDecoration(
              labelText: '提醒内容',
              hintText: '1分钟后提醒我喝水',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isParsing || voiceBusy ? null : _parse,
                    icon: _isParsing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: const Text('解析提醒'),
                  ),
                ),
              ),
              if (voiceConfigured) ...[
                const SizedBox(width: 12),
                SizedBox.square(
                  dimension: 48,
                  child: Tooltip(
                    message: isRecording ? '停止并识别' : '开始语音输入',
                    child: IconButton.filledTonal(
                      onPressed: switch (_voiceState) {
                        _VoiceInputState.idle => _startRecording,
                        _VoiceInputState.recording => _stopRecording,
                        _ => null,
                      },
                      icon: switch (_voiceState) {
                        _VoiceInputState.recording => const Icon(Icons.stop),
                        _VoiceInputState.starting ||
                        _VoiceInputState.transcribing ||
                        _VoiceInputState.cancelling =>
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        _ => const Icon(Icons.mic_none),
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Visibility(
                  visible: isRecording,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainState: true,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Tooltip(
                      message: '取消录音',
                      child: IconButton(
                        onPressed: _cancelRecording,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/quick_create_draft.dart';
import '../domain/quick_create_result.dart';
import '../domain/voice_input_controller.dart';

class QuickCreateSheet extends StatefulWidget {
  const QuickCreateSheet({
    required this.createDraft,
    this.onParsed,
    this.onCancel,
    this.voiceInputController,
    this.initialText,
    super.key,
  });

  final Future<QuickCreateDraft> Function(String text) createDraft;
  final ValueChanged<QuickCreateResult>? onParsed;
  final VoidCallback? onCancel;
  final VoiceInputController? voiceInputController;
  final String? initialText;

  @override
  State<QuickCreateSheet> createState() => _QuickCreateSheetState();
}

class _QuickCreateSheetState extends State<QuickCreateSheet> {
  late final _textController = TextEditingController(text: widget.initialText);
  bool _isParsing = false;
  bool _isVoiceActionInFlight = false;
  String? _parseError;
  String? _voiceActionError;

  VoiceInputController? get _voice => widget.voiceInputController;

  @override
  void initState() {
    super.initState();
    _voice?.addListener(_onVoiceStateChanged);
  }

  @override
  void didUpdateWidget(covariant QuickCreateSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceInputController == widget.voiceInputController) return;
    oldWidget.voiceInputController?.removeListener(_onVoiceStateChanged);
    _voice?.addListener(_onVoiceStateChanged);
  }

  @override
  void dispose() {
    final voice = _voice;
    voice?.removeListener(_onVoiceStateChanged);
    if (voice?.phase == VoiceInputPhase.recording) {
      unawaited(_cancelVoiceOnDispose(voice!));
    }
    _textController.dispose();
    super.dispose();
  }

  Future<void> _cancelVoiceOnDispose(VoiceInputController voice) async {
    try {
      await voice.cancel();
    } catch (_) {
      // The sheet cannot surface a cleanup error after it has been dismissed.
    }
  }

  void _onVoiceStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _parse() async {
    final sourceText = _textController.text.trim();
    if (sourceText.isEmpty ||
        _isParsing ||
        _voice?.phase == VoiceInputPhase.transcribing) {
      return;
    }
    setState(() {
      _isParsing = true;
      _parseError = null;
    });
    try {
      final draft = await widget.createDraft(sourceText);
      if (!mounted) return;
      widget.onParsed?.call(
        QuickCreateResult(sourceText: sourceText, draft: draft),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _parseError = '暂时无法解析，请检查网络后重试');
      }
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<void> _handleVoiceAction() async {
    final voice = _voice;
    if (voice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('语音输入暂不可用'), duration: Duration(seconds: 2)),
      );
      return;
    }
    if (_isVoiceActionInFlight ||
        (voice.phase != VoiceInputPhase.idle &&
            voice.phase != VoiceInputPhase.recording)) {
      return;
    }
    setState(() {
      _isVoiceActionInFlight = true;
      _voiceActionError = null;
    });
    try {
      if (voice.phase == VoiceInputPhase.idle) {
        await voice.start();
      } else {
        final textAtTranscriptionStart = _textController.text;
        final transcript = await voice.stopAndTranscribe();
        if (!mounted ||
            transcript == null ||
            transcript.trim().isEmpty ||
            _textController.text != textAtTranscriptionStart) {
          return;
        }
        _textController.text = transcript.trim();
        setState(() => _parseError = null);
        await _parse();
      }
    } catch (_) {
      if (mounted) setState(() => _voiceActionError = '语音输入失败，请重试');
    } finally {
      if (mounted) setState(() => _isVoiceActionInFlight = false);
    }
  }

  Future<void> _retryVoice() async {
    final voice = _voice;
    if (voice == null || _isVoiceActionInFlight) return;
    setState(() {
      _isVoiceActionInFlight = true;
      _voiceActionError = null;
    });
    try {
      await voice.retry();
    } catch (_) {
      if (mounted) setState(() => _voiceActionError = '语音输入失败，请重试');
    } finally {
      if (mounted) setState(() => _isVoiceActionInFlight = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await _voice?.cancel();
    } catch (_) {
      // The sheet still closes because abandoning input must not retain focus.
    }
    if (!mounted) return;
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      onCancel();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final voice = _voice;
    final phase = voice?.phase ?? VoiceInputPhase.idle;
    final hasVoiceFailure =
        phase == VoiceInputPhase.failure || _voiceActionError != null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Material(
          key: const Key('quick-create-panel'),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              key: const Key('quick-create-scroll'),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '快速创建',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: TextButton(
                              onPressed: _cancel,
                              child: const Text('取消'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('quick-create-input'),
                        controller: _textController,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 500,
                        enabled: !_isParsing,
                        decoration: const InputDecoration(
                          hintText: '例如：1分钟后提醒我喝水',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: _buildStatusRegion(
                          context: context,
                          voice: voice,
                          phase: phase,
                          hasVoiceFailure: hasVoiceFailure,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Semantics(
                            button: true,
                            label: '语音输入',
                            child: IconButton(
                              tooltip: '语音输入',
                              onPressed: _isParsing ||
                                      _isVoiceActionInFlight ||
                                      phase == VoiceInputPhase.transcribing ||
                                      hasVoiceFailure
                                  ? null
                                  : _handleVoiceAction,
                              icon: Icon(
                                phase == VoiceInputPhase.recording
                                    ? LucideIcons.square
                                    : LucideIcons.mic,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Expanded(child: SizedBox.shrink()),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _textController,
                            builder: (context, value, child) {
                              final canParse = value.text.trim().isNotEmpty &&
                                  !_isParsing &&
                                  !_isVoiceActionInFlight &&
                                  phase != VoiceInputPhase.transcribing;
                              return SizedBox(
                                height: 48,
                                child: FilledButton(
                                  onPressed: canParse ? _parse : null,
                                  child: _isParsing
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('继续'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildStatusRegion({
    required BuildContext context,
    required VoiceInputController? voice,
    required VoiceInputPhase phase,
    required bool hasVoiceFailure,
  }) {
    final theme = Theme.of(context);
    if (_parseError != null) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          _parseError!,
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    }
    if (_isVoiceActionInFlight) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('正在处理语音输入'),
      );
    }
    if (hasVoiceFailure) {
      return _buildVoiceFailure(
          context, voice?.errorMessage ?? _voiceActionError);
    }
    return switch (phase) {
      VoiceInputPhase.recording => Align(
          alignment: Alignment.centerLeft,
          child: Text('停止录音 ${_formatDuration(voice!.elapsed)}'),
        ),
      VoiceInputPhase.transcribing => const Align(
          alignment: Alignment.centerLeft,
          child: Text('正在转写'),
        ),
      VoiceInputPhase.failure => const SizedBox.shrink(),
      VoiceInputPhase.idle => const SizedBox.shrink(),
    };
  }

  Widget _buildVoiceFailure(BuildContext context, String? message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message ?? '语音输入失败',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        SizedBox(
          height: 44,
          child: TextButton(
            onPressed: _isVoiceActionInFlight ? null : _retryVoice,
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }
}

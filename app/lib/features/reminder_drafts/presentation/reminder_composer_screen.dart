import 'package:flutter/material.dart';

import '../../../platform/notifications/reminder_notification_scheduler.dart';
import '../../quick_create/domain/quick_create_result.dart';
import '../../quick_create/domain/voice_input_controller.dart';
import '../../quick_create/presentation/quick_create_sheet.dart';
import '../../reminders/domain/reminder.dart' show ReminderCreationResult;
import '../application/reminder_creation_service.dart';
import '../domain/reminder_draft.dart';
import 'reminder_draft_screen.dart';

class ReminderComposerScreen extends StatefulWidget {
  const ReminderComposerScreen({
    required this.createDraft,
    this.confirmDraft,
    this.notificationScheduler,
    this.reminderCreationService,
    this.voiceInputController,
    this.now,
    super.key,
  }) : assert(confirmDraft != null || reminderCreationService != null);

  final Future<ReminderDraft> Function(String) createDraft;
  final Future<String> Function(String)? confirmDraft;
  final ReminderNotificationScheduler? notificationScheduler;
  final ReminderCreationService? reminderCreationService;
  final VoiceInputController? voiceInputController;
  final DateTime? now;

  @override
  State<ReminderComposerScreen> createState() => _ReminderComposerScreenState();
}

class _ReminderComposerScreenState extends State<ReminderComposerScreen> {
  ReminderDraft? _draft;
  String? _sourceText;
  late final ReminderCreationService _creationService =
      widget.reminderCreationService ??
          ReminderCreationService(
            confirmDraft: widget.confirmDraft!,
            notificationScheduler: widget.notificationScheduler,
          );

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null) return;
    try {
      final result = await _creationService.confirmWithResult(draft);
      if (!mounted) return;
      switch (result.outcome) {
        case CreationOutcome.created:
          _complete(result, notificationScheduled: false);
          return;
        case CreationOutcome.notificationScheduled:
          _complete(result, notificationScheduled: true);
          return;
        case CreationOutcome.notificationNotScheduled:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提醒已创建，但手机通知未安排')),
          );
      }
    } on ReminderNotificationSchedulingException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒已创建，但手机通知未安排')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败，请稍后重试')),
      );
    }
  }

  void _complete(
    ReminderCreationServiceResult result, {
    required bool notificationScheduled,
  }) {
    final creationResult = ReminderCreationResult(
      reminderId: result.reminderId,
      notificationScheduled: notificationScheduled,
    );
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(creationResult);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notificationScheduled ? '提醒已创建，通知已安排' : '提醒已创建，但手机通知未安排',
        ),
      ),
    );
  }

  void _edit() {
    setState(() {
      _draft = null;
    });
  }

  void _showDraft(QuickCreateResult result) {
    setState(() {
      _draft = result.draft;
      _sourceText = result.sourceText;
    });
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: QuickCreateSheet(
        createDraft: widget.createDraft,
        onParsed: _showDraft,
        voiceInputController: widget.voiceInputController,
        initialText: _sourceText,
      ),
    );
  }
}

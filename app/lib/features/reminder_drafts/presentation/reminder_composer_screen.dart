import 'package:flutter/material.dart';

import '../../../platform/notifications/reminder_notification_scheduler.dart';
import '../../../platform/notifications/local_notification_scheduler.dart';
import '../../plans/domain/plan_models.dart';
import '../../quick_create/domain/quick_create_draft.dart';
import '../../quick_create/domain/quick_create_result.dart';
import '../../quick_create/domain/voice_input_controller.dart';
import '../../quick_create/presentation/quick_create_sheet.dart';
import '../../quick_create/presentation/workflow_draft_screen.dart';
import '../../reminders/domain/reminder.dart' show ReminderCreationResult;
import '../application/reminder_creation_service.dart';
import 'reminder_draft_screen.dart';

class ReminderComposerScreen extends StatefulWidget {
  const ReminderComposerScreen({
    required this.createDraft,
    this.confirmDraft,
    this.confirmWorkflowDraft,
    this.answerWorkflowDraft,
    this.notificationScheduler,
    this.reminderCreationService,
    this.voiceInputController,
    this.now,
    this.planNotificationScheduler,
    this.loadPlan,
    super.key,
  }) : assert(confirmDraft != null || reminderCreationService != null);

  final Future<QuickCreateDraft> Function(String) createDraft;
  final Future<String> Function(String)? confirmDraft;
  final Future<String> Function(String)? confirmWorkflowDraft;
  final Future<WorkflowDraft> Function(String draftId, String answer)?
      answerWorkflowDraft;
  final ReminderNotificationScheduler? notificationScheduler;
  final ReminderCreationService? reminderCreationService;
  final VoiceInputController? voiceInputController;
  final DateTime? now;
  final PlanNotificationScheduler? planNotificationScheduler;
  final Future<PlanDetail> Function(String id)? loadPlan;

  @override
  State<ReminderComposerScreen> createState() => _ReminderComposerScreenState();
}

class _ReminderComposerScreenState extends State<ReminderComposerScreen> {
  QuickCreateDraft? _draft;
  String? _sourceText;
  late final ReminderCreationService _creationService =
      widget.reminderCreationService ??
          ReminderCreationService(
            confirmDraft: widget.confirmDraft!,
            notificationScheduler: widget.notificationScheduler,
          );

  Future<void> _confirm() async {
    final draft = _draft?.reminder;
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

  Future<void> _reparse(String text) async {
    final draft = await widget.createDraft(text);
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _sourceText = text;
    });
  }

  Future<void> _confirmWorkflow(WorkflowDraft workflow) async {
    final confirm = widget.confirmWorkflowDraft;
    if (confirm == null || !workflow.canConfirm) return;
    try {
      final planId = await confirm(workflow.id);
      final scheduled = await _schedulePlan(planId);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(scheduled);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scheduled ? '计划已确认，手机通知已安排' : '计划已确认，但手机通知未安排',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('确认失败，请稍后重试')),
      );
    }
  }

  Future<bool> _schedulePlan(String planId) async {
    final scheduler = widget.planNotificationScheduler;
    final load = widget.loadPlan;
    if (scheduler == null || load == null) return false;
    try {
      final plan = await load(planId);
      final schedule = plan.notificationSchedule;
      if (schedule == null) return false;
      await scheduler.schedulePlan(planId: planId, schedule: schedule);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<WorkflowDraft> _answerWorkflow(String answer) async {
    final workflow = _draft!.workflow!;
    return widget.answerWorkflowDraft!(workflow.id, answer);
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
      if (draft.isWorkflow) {
        return WorkflowDraftScreen(
          sourceText: _sourceText ?? '',
          draft: draft.workflow!,
          onConfirm: _confirmWorkflow,
          onReparse: _reparse,
          onAnswer: widget.answerWorkflowDraft != null ? _answerWorkflow : null,
        );
      }
      return ReminderDraftScreen(
        sourceText: _sourceText ?? '',
        draft: draft.reminder!,
        onConfirm: _confirm,
        onReparse: _reparse,
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

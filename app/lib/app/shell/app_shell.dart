import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/auth/domain/auth_models.dart';
import '../../features/medicine_cabinet/data/medicine_repository.dart';
import '../../features/medicine_cabinet/domain/medicine_models.dart';
import '../../features/medicine_cabinet/domain/medicine_description_draft.dart';
import '../../features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';
import '../../features/plans/data/plan_repository.dart';
import '../../features/plans/presentation/plans_screen.dart';
import '../../features/quick_create/domain/quick_create_draft.dart';
import '../../features/quick_create/domain/quick_create_result.dart';
import '../../features/quick_create/domain/voice_input_controller.dart';
import '../../features/quick_create/presentation/quick_create_sheet.dart';
import '../../features/quick_create/presentation/workflow_draft_screen.dart';
import '../../features/reminder_drafts/application/reminder_creation_service.dart';
import '../../features/reminder_drafts/domain/reminder_draft.dart';
import '../../features/reminder_drafts/presentation/reminder_draft_screen.dart';
import '../../features/today/data/action_center_api.dart';
import '../../features/today/data/today_repository.dart';
import '../../features/today/domain/today_models.dart';
import '../../features/today/presentation/today_screen.dart';
import '../../platform/notifications/local_notification_scheduler.dart';
import '../settings/settings_screen.dart';
import '../theme/app_spacing.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.todayRepository,
    required this.planRepository,
    required this.medicineRepository,
    required this.user,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onChangePassword,
    required this.onLogout,
    this.onOpenReminderManager,
    this.createDraft,
    this.confirmWorkflowDraft,
    this.answerWorkflowDraft,
    this.reminderCreationService,
    this.voiceInputController,
    this.onDeleteBatch,
    this.onCaptureMedicine,
    this.onCaptureMedicinePhoto,
    this.captureAvailability = MedicineCaptureAvailability.unavailable,
    this.onOpenSystemSettings,
    this.actionCenterActions,
    this.onCorrectBatchExpiry,
    this.onCreateBatch,
    this.onParseMedicineDescription,
    this.planNotificationScheduler,
    super.key,
  });

  final TodayRepository todayRepository;
  final PlanRepository planRepository;
  final MedicineRepository medicineRepository;
  final AuthUser user;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function(
    String currentPassword,
    String newPassword,
    String newPasswordConfirm,
  ) onChangePassword;
  final Future<void> Function() onLogout;
  final VoidCallback? onOpenReminderManager;
  final Future<QuickCreateDraft> Function(String text)? createDraft;
  final Future<String> Function(String draftId)? confirmWorkflowDraft;
  final Future<WorkflowDraft> Function(String draftId, String answer)?
      answerWorkflowDraft;
  final ReminderCreationService? reminderCreationService;
  final VoiceInputController? voiceInputController;
  final Future<void> Function(MedicineBatch batch)? onDeleteBatch;
  final Future<bool> Function()? onCaptureMedicine;
  final Future<List<int>?> Function()? onCaptureMedicinePhoto;
  final MedicineCaptureAvailability captureAvailability;
  final VoidCallback? onOpenSystemSettings;
  final ActionCenterActions? actionCenterActions;
  final Future<void> Function(MedicineBatch batch, DateTime expiryDate)?
      onCorrectBatchExpiry;
  final Future<void> Function(MedicineBatchInput input)? onCreateBatch;
  final Future<MedicineDescriptionDraft> Function(String text)?
      onParseMedicineDescription;
  final PlanNotificationScheduler? planNotificationScheduler;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _selectedIndex = 0;

  void _selectDestination(int index) {
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          user: widget.user,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onChangePassword: widget.onChangePassword,
          onLogout: widget.onLogout,
        ),
      ),
    );
  }

  Future<void> _openQuickCreate({String? initialText}) async {
    final createDraft = widget.createDraft;
    final service = widget.reminderCreationService;
    if (createDraft == null || service == null) return;
    final result = await showModalBottomSheet<QuickCreateResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => QuickCreateSheet(
        createDraft: createDraft,
        initialText: initialText,
        voiceInputController: widget.voiceInputController,
        onParsed: (value) => Navigator.of(sheetContext).pop(value),
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
    );
    if (mounted && result != null) await _showDraft(result, service);
  }

  Future<void> _reparseDraft(
    ReminderCreationService service,
    String text,
  ) async {
    final createDraft = widget.createDraft;
    if (createDraft == null) {
      throw StateError('quick create is unavailable');
    }
    final draft = await createDraft(text);
    if (!mounted) return;
    Navigator.of(context).pop();
    await _showDraft(
      QuickCreateResult(sourceText: text, draft: draft),
      service,
    );
  }

  Future<void> _showDraft(
    QuickCreateResult result,
    ReminderCreationService service,
  ) async {
    final draft = result.draft;
    if (draft.isWorkflow) {
      final workflow = draft.workflow!;
      final answerWorkflowDraft = widget.answerWorkflowDraft;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => WorkflowDraftScreen(
            sourceText: result.sourceText,
            draft: workflow,
            onReparse: (text) => _reparseDraft(service, text),
            onConfirm: _confirmWorkflowDraft,
            onAnswer: answerWorkflowDraft == null
                ? null
                : (answer) => answerWorkflowDraft(workflow.id, answer),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReminderDraftScreen(
          sourceText: result.sourceText,
          draft: draft.reminder!,
          onReparse: (text) => _reparseDraft(service, text),
          onConfirm: () => _confirmDraft(draft.reminder!, service),
        ),
      ),
    );
  }

  Future<void> _confirmWorkflowDraft(WorkflowDraft draft) async {
    final confirm = widget.confirmWorkflowDraft;
    if (confirm == null || !draft.canConfirm) return;
    try {
      final planId = await confirm(draft.id);
      final notificationScheduled = await _schedulePlanNotification(planId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notificationScheduled ? '计划已确认，手机通知已安排' : '计划已确认，但手机通知未安排',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('确认失败，请稍后重试')),
        );
      }
    }
  }

  Future<bool> _schedulePlanNotification(String planId) async {
    final scheduler = widget.planNotificationScheduler;
    if (scheduler == null) return false;
    try {
      final detail = await widget.planRepository.getById(planId);
      final schedule = detail.notificationSchedule;
      if (schedule == null) return false;
      await scheduler.schedulePlan(planId: planId, schedule: schedule);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirmDraft(
    ReminderDraft draft,
    ReminderCreationService service,
  ) async {
    try {
      final outcome = await service.confirm(draft);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (outcome) {
            CreationOutcome.created => '提醒已创建',
            CreationOutcome.notificationScheduled => '提醒已创建，通知已安排',
            CreationOutcome.notificationNotScheduled => '提醒已创建，但手机通知未安排',
          }),
        ),
      );
    } on ReminderNotificationSchedulingException {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提醒已创建，但手机通知未安排')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _handleAttentionAction(AttentionItem item) async {
    final actions = widget.actionCenterActions;
    final target = item.actionTarget;
    if (actions == null || target == null) {
      _showSnackBar('这个动作暂时只能查看，稍后会接入处理入口');
      return;
    }

    try {
      if (target.resource == 'medication_occurrence') {
        await actions.markMedicationTaken(target.id);
        _showSnackBar('已记录服药');
      } else if (target.resource == 'inventory_batch') {
        await actions.handleExpiryBatch(target.id);
        _showSnackBar('已处理有效期提醒');
      } else {
        _showSnackBar('暂不支持直接处理这个事项');
      }
    } catch (_) {
      _showSnackBar('处理失败，请稍后重试');
      rethrow;
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.breakpointMedium;
    final tabs = [
      KeyedSubtree(
        key: const PageStorageKey<String>('today-tab'),
        child: TodayScreen(
          repository: widget.todayRepository,
          onOpenReminderManager: widget.onOpenReminderManager,
          onOpenSettings: _openSettings,
          onOpenAttention: _handleAttentionAction,
        ),
      ),
      KeyedSubtree(
        key: const PageStorageKey<String>('periodic-plans-tab'),
        child: PlansScreen(
          repository: widget.planRepository,
          onOpenSettings: _openSettings,
          notificationScheduler: widget.planNotificationScheduler,
          onEditPlan: (sourceText) => _openQuickCreate(initialText: sourceText),
        ),
      ),
      KeyedSubtree(
        key: const PageStorageKey<String>('medicine-tab'),
        child: MedicineCabinetScreen(
          repository: widget.medicineRepository,
          onDeleteBatch: widget.onDeleteBatch,
          captureAvailability: widget.captureAvailability,
          onCapture: widget.onCaptureMedicine,
          onCapturePhoto: widget.onCaptureMedicinePhoto,
          onOpenSystemSettings: widget.onOpenSystemSettings,
          onCorrectBatchExpiry: widget.onCorrectBatchExpiry,
          onCreateBatch: widget.onCreateBatch,
          onParseDescription: widget.onParseMedicineDescription,
          voiceInputController: widget.voiceInputController,
          onOpenSettings: _openSettings,
        ),
      ),
    ];
    final content = IndexedStack(index: _selectedIndex, children: tabs);
    final showQuickCreate = _selectedIndex == 0;
    final quickCreate = _QuickCreateBar(
      enabled:
          widget.createDraft != null && widget.reminderCreationService != null,
      onPressed: _openQuickCreate,
      compact: compact,
    );

    if (compact) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(child: content),
            if (showQuickCreate) quickCreate,
            NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              destinations: _destinations,
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 96,
            child: Column(
              children: [
                Expanded(
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectDestination,
                    labelType: NavigationRailLabelType.all,
                    destinations: _railDestinations,
                  ),
                ),
                if (showQuickCreate) quickCreate,
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(LucideIcons.calendarClock),
      label: '今天',
    ),
    NavigationDestination(icon: Icon(LucideIcons.repeat2), label: '周期'),
    NavigationDestination(icon: Icon(LucideIcons.pill), label: '药箱'),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(LucideIcons.calendarClock),
      label: Text('今天'),
    ),
    NavigationRailDestination(
      icon: Icon(LucideIcons.repeat2),
      label: Text('周期'),
    ),
    NavigationRailDestination(icon: Icon(LucideIcons.pill), label: Text('药箱')),
  ];
}

class _QuickCreateBar extends StatelessWidget {
  const _QuickCreateBar({
    required this.enabled,
    required this.onPressed,
    required this.compact,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const Key('quick-create-bar'),
        height: 56,
        child: Center(
          child: compact
              ? FilledButton.icon(
                  key: const Key('quick-create-action'),
                  onPressed: enabled ? onPressed : null,
                  icon: const Icon(LucideIcons.plus),
                  label: const Text('快速创建'),
                )
              : IconButton(
                  key: const Key('quick-create-action'),
                  tooltip: '快速创建提醒',
                  onPressed: enabled ? onPressed : null,
                  icon: const Icon(LucideIcons.plus),
                ),
        ),
      );
}

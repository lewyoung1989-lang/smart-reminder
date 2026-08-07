import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/auth/domain/auth_models.dart';
import '../../features/medicine_cabinet/data/medicine_repository.dart';
import '../../features/medicine_cabinet/domain/medicine_models.dart';
import '../../features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';
import '../../features/plans/data/plan_repository.dart';
import '../../features/plans/presentation/plans_screen.dart';
import '../../features/quick_create/domain/quick_create_result.dart';
import '../../features/quick_create/domain/voice_input_controller.dart';
import '../../features/quick_create/presentation/quick_create_sheet.dart';
import '../../features/reminder_drafts/application/reminder_creation_service.dart';
import '../../features/reminder_drafts/domain/reminder_draft.dart';
import '../../features/reminder_drafts/presentation/reminder_draft_screen.dart';
import '../../features/today/data/today_repository.dart';
import '../../features/today/presentation/today_screen.dart';
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
    this.reminderCreationService,
    this.voiceInputController,
    this.onDeleteBatch,
    this.onCaptureMedicine,
    this.captureAvailability = MedicineCaptureAvailability.unavailable,
    this.onOpenSystemSettings,
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
  final Future<ReminderDraft> Function(String text)? createDraft;
  final ReminderCreationService? reminderCreationService;
  final VoiceInputController? voiceInputController;
  final Future<void> Function(MedicineBatch batch)? onDeleteBatch;
  final Future<bool> Function()? onCaptureMedicine;
  final MedicineCaptureAvailability captureAvailability;
  final VoidCallback? onOpenSystemSettings;

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

  Future<void> _openQuickCreate() async {
    final createDraft = widget.createDraft;
    final service = widget.reminderCreationService;
    if (createDraft == null || service == null) return;
    final result = await showModalBottomSheet<QuickCreateResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => QuickCreateSheet(
        createDraft: createDraft,
        voiceInputController: widget.voiceInputController,
        onParsed: (value) => Navigator.of(sheetContext).pop(value),
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
    );
    if (mounted && result != null) await _showDraft(result, service);
  }

  Future<void> _showDraft(
    QuickCreateResult result,
    ReminderCreationService service,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReminderDraftScreen(
          sourceText: result.sourceText,
          draft: result.draft,
          onEdit: () => Navigator.of(context).pop(),
          onConfirm: () => _confirmDraft(result.draft, service),
        ),
      ),
    );
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
        ),
      ),
      KeyedSubtree(
        key: const PageStorageKey<String>('plans-tab'),
        child: PlansScreen(
          repository: widget.planRepository,
          onOpenSettings: _openSettings,
        ),
      ),
      KeyedSubtree(
        key: const PageStorageKey<String>('medicine-tab'),
        child: MedicineCabinetScreen(
          repository: widget.medicineRepository,
          onDeleteBatch: widget.onDeleteBatch,
          captureAvailability: widget.captureAvailability,
          onCapture: widget.onCaptureMedicine,
          onOpenSystemSettings: widget.onOpenSystemSettings,
          onOpenSettings: _openSettings,
        ),
      ),
    ];
    final content = IndexedStack(index: _selectedIndex, children: tabs);
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
            quickCreate,
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
                quickCreate,
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
    NavigationDestination(icon: Icon(LucideIcons.bell), label: '计划'),
    NavigationDestination(icon: Icon(LucideIcons.pill), label: '药箱'),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(LucideIcons.calendarClock),
      label: Text('今天'),
    ),
    NavigationRailDestination(icon: Icon(LucideIcons.bell), label: Text('计划')),
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

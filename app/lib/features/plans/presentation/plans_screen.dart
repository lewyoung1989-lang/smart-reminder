import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/data/feature_unavailable_exception.dart';
import '../../../ui/components/app_content_state.dart';
import '../../../ui/components/app_list_row.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_segmented_control.dart';
import '../../../ui/components/app_status_banner.dart';
import '../data/plan_repository.dart';
import '../domain/plan_models.dart';
import '../../../platform/notifications/local_notification_scheduler.dart';
import 'plan_detail_screen.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({
    required this.repository,
    this.onOpenSettings,
    this.onOpenPlan,
    this.notificationScheduler,
    this.onEditPlan,
    super.key,
  });

  final PlanRepository repository;
  final VoidCallback? onOpenSettings;
  final ValueChanged<PlanSummary>? onOpenPlan;
  final PlanNotificationScheduler? notificationScheduler;
  final ValueChanged<String>? onEditPlan;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  PlanCollection? _collection;
  PlanDetail? _selectedDetail;
  String? _selectedPlanId;
  PlanStatus _selectedStatus = PlanStatus.active;
  PlanKind? _selectedKind;
  Object? _error;
  Object? _detailError;
  bool _isLoading = true;
  var _isDetailLoading = false;
  var _loadGeneration = 0;
  var _detailLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlansScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _load(clearCollection: true);
  }

  Future<void> _load({bool clearCollection = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
      if (clearCollection) {
        _collection = null;
        _selectedDetail = null;
        _selectedPlanId = null;
        _detailError = null;
        _isDetailLoading = false;
        _detailLoadGeneration += 1;
      }
    });
    try {
      final collection = await widget.repository.load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _collection = collection;
        _selectedPlanId ??= _filtered(collection.items).firstOrNull?.id;
      });
      await _loadSelectedDetail(generation: generation);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSelectedDetail({int? generation}) async {
    final id = _selectedPlanId;
    if (id == null) {
      setState(() {
        _selectedDetail = null;
        _detailError = null;
        _isDetailLoading = false;
      });
      return;
    }
    final detailGeneration = ++_detailLoadGeneration;
    setState(() {
      _selectedDetail = null;
      _detailError = null;
      _isDetailLoading = true;
    });
    try {
      final detail = await widget.repository.getById(id);
      if (!mounted ||
          detailGeneration != _detailLoadGeneration ||
          (generation != null && generation != _loadGeneration)) {
        return;
      }
      if (_selectedPlanId == id) {
        setState(() => _selectedDetail = detail);
      }
    } catch (error) {
      if (!mounted ||
          detailGeneration != _detailLoadGeneration ||
          (generation != null && generation != _loadGeneration)) {
        return;
      }
      if (_selectedPlanId == id) setState(() => _detailError = error);
    } finally {
      if (mounted && detailGeneration == _detailLoadGeneration) {
        setState(() => _isDetailLoading = false);
      }
    }
  }

  List<PlanSummary> _filtered(List<PlanSummary> plans) {
    return plans
        .where((plan) => plan.status == _selectedStatus)
        .where((plan) => _selectedKind == null || plan.kind == _selectedKind)
        .toList();
  }

  void _setStatus(PlanStatus status) {
    setState(() {
      _selectedStatus = status;
      final visible = _filtered(_collection?.items ?? const []);
      if (!visible.any((plan) => plan.id == _selectedPlanId)) {
        _selectedPlanId = visible.firstOrNull?.id;
        _selectedDetail = null;
      }
    });
    _loadSelectedDetail();
  }

  void _setKind(PlanKind? kind) {
    setState(() {
      _selectedKind = kind;
      final visible = _filtered(_collection?.items ?? const []);
      if (!visible.any((plan) => plan.id == _selectedPlanId)) {
        _selectedPlanId = visible.firstOrNull?.id;
        _selectedDetail = null;
      }
    });
    _loadSelectedDetail();
  }

  Future<void> _openPlan(PlanSummary plan, bool expanded) async {
    if (widget.onOpenPlan != null) {
      widget.onOpenPlan!(plan);
      return;
    }
    if (expanded) {
      setState(() {
        _selectedPlanId = plan.id;
        _selectedDetail = null;
      });
      await _loadSelectedDetail();
      return;
    }
    try {
      final detail = await widget.repository.getById(plan.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _detailScreen(detail, compact: true),
        ),
      );
      if (mounted) await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('计划详情加载失败，请稍后重试')),
      );
    }
  }

  PlanDetailScreen _detailScreen(PlanDetail detail, {required bool compact}) {
    final actions = widget.repository is PlanActions
        ? widget.repository as PlanActions
        : null;
    return PlanDetailScreen(
      detail: detail,
      onPause: actions == null
          ? null
          : () => _pausePlan(actions, detail, compact: compact),
      onResume: actions == null
          ? null
          : () => _resumePlan(actions, detail, compact: compact),
      onDelete: actions == null
          ? null
          : () => _deletePlan(actions, detail, compact: compact),
      onEdit: widget.onEditPlan == null || detail.sourceText.trim().isEmpty
          ? null
          : () => _editPlan(detail, compact: compact),
    );
  }

  Future<void> _pausePlan(
    PlanActions actions,
    PlanDetail detail, {
    required bool compact,
  }) async {
    await actions.pause(detail.summary.id);
    await _cancelPlanNotification(
      detail.summary.id,
      failureMessage: '计划已暂停，但手机通知取消失败',
    );
    await _finishMutation(compact: compact, message: '计划已暂停');
  }

  Future<void> _resumePlan(
    PlanActions actions,
    PlanDetail detail, {
    required bool compact,
  }) async {
    final updated = await actions.resume(detail.summary.id);
    final scheduled = await _schedulePlanNotification(updated);
    await _finishMutation(
      compact: compact,
      message: scheduled ? '计划已恢复，手机通知已安排' : '计划已恢复，但手机通知未安排',
    );
  }

  Future<void> _deletePlan(
    PlanActions actions,
    PlanDetail detail, {
    required bool compact,
  }) async {
    await actions.delete(detail.summary.id);
    await _cancelPlanNotification(
      detail.summary.id,
      failureMessage: '计划已删除，但手机通知取消失败',
    );
    _selectedPlanId = null;
    await _finishMutation(compact: compact, message: '计划已删除');
  }

  Future<bool> _confirmAndDeleteFromList(
    PlanActions actions,
    PlanSummary plan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这个计划？'),
        content: Text('“${plan.title}”删除后无法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('confirm-delete-plan'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await actions.delete(plan.id);
      await _cancelPlanNotification(
        plan.id,
        failureMessage: '计划已删除，但手机通知取消失败',
      );
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请稍后重试')),
        );
      }
      return false;
    }
  }

  void _finishListDeletion(PlanSummary plan) {
    final collection = _collection;
    if (collection != null) {
      setState(() {
        _collection = PlanCollection(
          items: collection.items
              .where((item) => item.id != plan.id)
              .toList(growable: false),
          isOffline: collection.isOffline,
        );
        if (_selectedPlanId == plan.id) {
          _selectedPlanId = null;
          _selectedDetail = null;
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('计划已删除')),
    );
    _load();
  }

  void _editPlan(PlanDetail detail, {required bool compact}) {
    if (compact) Navigator.of(context).pop();
    widget.onEditPlan?.call(detail.sourceText);
  }

  Future<bool> _schedulePlanNotification(PlanDetail detail) async {
    final scheduler = widget.notificationScheduler;
    final schedule = detail.notificationSchedule;
    if (scheduler == null || schedule == null) return false;
    try {
      await scheduler.cancelPlan(planId: detail.summary.id);
      await scheduler.schedulePlan(
        planId: detail.summary.id,
        schedule: schedule,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _cancelPlanNotification(
    String planId, {
    required String failureMessage,
  }) async {
    try {
      await widget.notificationScheduler?.cancelPlan(planId: planId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failureMessage)),
        );
      }
    }
  }

  Future<void> _finishMutation({
    required bool compact,
    required String message,
  }) async {
    if (compact && mounted) Navigator.of(context).pop();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await _load();
    }
  }

  Future<void> _showKindFilter() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('计划类型', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('当前状态：${_statusLabel(_selectedStatus)}'),
                const SizedBox(height: AppSpacing.sm),
                RadioGroup<_KindFilter>(
                  groupValue: _kindFilterFor(_selectedKind),
                  onChanged: (value) {
                    _setKind(_kindFor(value));
                    setSheetState(() {});
                  },
                  child: Column(
                    children: <Widget>[
                      _kindOption(_KindFilter.all, '全部类型'),
                      _kindOption(_KindFilter.medication, '用药'),
                      _kindOption(_KindFilter.departure, '出行'),
                      _kindOption(_KindFilter.reminder, '提醒'),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      _setKind(null);
                      setSheetState(() {});
                    },
                    child: const Text('清除筛选'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kindOption(_KindFilter kind, String label) {
    return RadioListTile<_KindFilter>(
      value: kind,
      title: Text(label),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final expanded =
        MediaQuery.sizeOf(context).width >= AppSpacing.breakpointExpanded;
    final content = _collectionContent(context, expanded);
    if (expanded && _collection != null && _error == null) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: <Widget>[
              SizedBox(width: 380, child: content),
              const VerticalDivider(width: 1),
              Expanded(child: _detailPane()),
            ],
          ),
        ),
      );
    }
    return Scaffold(body: SafeArea(child: content));
  }

  Widget _collectionContent(BuildContext context, bool expanded) {
    final collection = _collection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          key: const ValueKey('plans-fixed-header'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: AppPageHeader(
            title: '周期计划',
            largeTitle: true,
            actions: <Widget>[
              IconButton(
                tooltip: '打开设置',
                onPressed: widget.onOpenSettings,
                icon: const Icon(LucideIcons.settings),
              ),
              IconButton(
                tooltip: '筛选计划',
                onPressed: _showKindFilter,
                icon: const Icon(LucideIcons.listFilter),
              ),
            ],
          ),
        ),
        if (collection != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppSegmentedControl<PlanStatus>(
              key: const ValueKey('plans-status-tabs'),
              value: _selectedStatus,
              options: _statusOptions(collection),
              onChanged: _setStatus,
            ),
          ),
        Expanded(
          child: CustomScrollView(
            key: const PageStorageKey('plans-list-scroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: _contentSlivers(context, expanded),
          ),
        ),
      ],
    );
  }

  List<AppSegment<PlanStatus>> _statusOptions(PlanCollection collection) {
    final counts = <PlanStatus, int>{
      for (final status in PlanStatus.values)
        status: collection.items.where((plan) => plan.status == status).length,
    };
    return <AppSegment<PlanStatus>>[
      AppSegment(
        value: PlanStatus.active,
        label: '运行中',
        count: counts[PlanStatus.active],
      ),
      AppSegment(
        value: PlanStatus.pending,
        label: '待确认',
        count: counts[PlanStatus.pending],
      ),
      AppSegment(
        value: PlanStatus.paused,
        label: '已暂停',
        count: counts[PlanStatus.paused],
      ),
    ];
  }

  List<Widget> _contentSlivers(BuildContext context, bool expanded) {
    final collection = _collection;
    if (collection == null) {
      if (_isLoading) return _stateSlivers(const AppContentState.loading());
      if (_error is FeatureUnavailableException) {
        return _stateSlivers(
          const AppContentState.unavailable(title: '计划暂时不可用', message: '请稍后再试'),
        );
      }
      if (_error != null) {
        return _stateSlivers(
          AppContentState.error(
            title: '计划加载失败',
            message: '请检查网络后重试',
            actionLabel: '重试',
            onAction: _load,
          ),
        );
      }
      return _stateSlivers(const AppContentState.loading());
    }
    final visible = _filtered(collection.items);
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
    ];
    if (collection.isOffline) {
      slivers.add(
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: AppStatusBanner(
              severity: AppStatusSeverity.offline,
              title: '正在显示上次同步计划',
            ),
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      slivers.addAll(_stateSlivers(const AppContentState.empty(
        title: '没有符合条件的周期计划',
        message: '调整状态或类型筛选后再查看',
      )));
      return slivers;
    }
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
        sliver: SliverToBoxAdapter(
          child: Column(
            children: <Widget>[
              for (var index = 0; index < visible.length; index += 1)
                _dismissiblePlanRow(
                  visible[index],
                  position: _positionFor(index, visible.length),
                  expanded: expanded,
                ),
            ],
          ),
        ),
      ),
    );
    return slivers;
  }

  Widget _dismissiblePlanRow(
    PlanSummary plan, {
    required AppListRowPosition position,
    required bool expanded,
  }) {
    final row = _PlanRow(
      plan: plan,
      position: position,
      onTap: () => _openPlan(plan, expanded),
    );
    final actions = widget.repository is PlanActions
        ? widget.repository as PlanActions
        : null;
    if (actions == null) return row;
    return Dismissible(
      key: ValueKey('dismiss-plan-${plan.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmAndDeleteFromList(actions, plan),
      onDismissed: (_) => _finishListDeletion(plan),
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Semantics(
          label: '删除计划',
          child: const Icon(LucideIcons.trash2, color: Colors.white),
        ),
      ),
      child: row,
    );
  }

  List<Widget> _stateSlivers(Widget state) => <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(child: state),
        ),
      ];

  Widget _detailPane() {
    final detail = _selectedDetail;
    if (detail != null) return _detailScreen(detail, compact: false);
    if (_isDetailLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: AppContentState.loading(),
      );
    }
    if (_detailError is FeatureUnavailableException) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: AppContentState.unavailable(
          title: '计划详情暂时不可用',
          message: '请稍后再试',
        ),
      );
    }
    if (_detailError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppContentState.error(
          title: '计划详情加载失败',
          message: '请稍后再试',
          actionLabel: '重试',
          onAction: _loadSelectedDetail,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: AppContentState.empty(
        title: '选择一个计划',
        message: '计划详情会显示在这里',
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(
      {required this.plan, required this.position, required this.onTap});

  final PlanSummary plan;
  final AppListRowPosition position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final statusColor = switch (plan.status) {
      PlanStatus.active => semantic.success,
      PlanStatus.pending => semantic.warning,
      PlanStatus.paused => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return AppListRow(
      icon: switch (plan.kind) {
        PlanKind.medication => LucideIcons.pill,
        PlanKind.departure => LucideIcons.route,
        PlanKind.reminder => LucideIcons.bell,
      },
      title: plan.title,
      subtitle: '${_formatTime(plan.nextRunAt)} · ${plan.subtitle}',
      statusText: _statusLabel(plan.status),
      statusColor: statusColor,
      position: position,
      onTap: onTap,
    );
  }
}

AppListRowPosition _positionFor(int index, int length) {
  if (length == 1) return AppListRowPosition.single;
  if (index == 0) return AppListRowPosition.first;
  if (index == length - 1) return AppListRowPosition.last;
  return AppListRowPosition.middle;
}

String _statusLabel(PlanStatus status) => switch (status) {
      PlanStatus.active => '运行中',
      PlanStatus.pending => '待确认',
      PlanStatus.paused => '已暂停',
    };

String _formatTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

extension on List<PlanSummary> {
  PlanSummary? get firstOrNull => isEmpty ? null : first;
}

enum _KindFilter { all, medication, departure, reminder }

_KindFilter _kindFilterFor(PlanKind? kind) => switch (kind) {
      null => _KindFilter.all,
      PlanKind.medication => _KindFilter.medication,
      PlanKind.departure => _KindFilter.departure,
      PlanKind.reminder => _KindFilter.reminder,
    };

PlanKind? _kindFor(_KindFilter? filter) => switch (filter) {
      _KindFilter.medication => PlanKind.medication,
      _KindFilter.departure => PlanKind.departure,
      _KindFilter.reminder => PlanKind.reminder,
      _KindFilter.all || null => null,
    };

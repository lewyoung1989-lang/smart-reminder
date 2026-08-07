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
import 'plan_detail_screen.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({
    required this.repository,
    this.onOpenSettings,
    this.onOpenPlan,
    super.key,
  });

  final PlanRepository repository;
  final VoidCallback? onOpenSettings;
  final ValueChanged<PlanSummary>? onOpenPlan;

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
        MaterialPageRoute(builder: (_) => PlanDetailScreen(detail: detail)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('计划详情加载失败，请稍后重试')),
      );
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
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: AppPageHeader(
              title: '计划',
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
        ),
        ..._contentSlivers(context, expanded),
      ],
    );
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
    final counts = <PlanStatus, int>{
      for (final status in PlanStatus.values)
        status: collection.items.where((plan) => plan.status == status).length,
    };
    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: AppSegmentedControl<PlanStatus>(
            value: _selectedStatus,
            options: <AppSegment<PlanStatus>>[
              AppSegment(
                  value: PlanStatus.active,
                  label: '运行中',
                  count: counts[PlanStatus.active]),
              AppSegment(
                  value: PlanStatus.pending,
                  label: '待确认',
                  count: counts[PlanStatus.pending]),
              AppSegment(
                  value: PlanStatus.paused,
                  label: '已暂停',
                  count: counts[PlanStatus.paused]),
            ],
            onChanged: _setStatus,
          ),
        ),
      ),
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
        title: '没有符合条件的计划',
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
                _PlanRow(
                  plan: visible[index],
                  position: _positionFor(index, visible.length),
                  onTap: () => _openPlan(visible[index], expanded),
                ),
            ],
          ),
        ),
      ),
    );
    return slivers;
  }

  List<Widget> _stateSlivers(Widget state) => <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(child: state),
        ),
      ];

  Widget _detailPane() {
    final detail = _selectedDetail;
    if (detail != null) return PlanDetailScreen(detail: detail);
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

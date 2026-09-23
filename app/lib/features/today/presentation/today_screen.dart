import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/data/feature_unavailable_exception.dart';
import '../../../ui/components/app_content_state.dart';
import '../../../ui/components/app_list_row.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_status_banner.dart';
import '../../../ui/components/app_status_tag.dart';
import '../data/today_repository.dart';
import '../domain/today_models.dart';

typedef AttentionActionCallback = Future<void> Function(AttentionItem item);
typedef AttentionInspectCallback = Future<void> Function(AttentionItem item);

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    required this.repository,
    this.now,
    this.onOpenSettings,
    this.onOpenReminderManager,
    this.onOpenAttention,
    this.onInspectAttention,
    this.onOpenTimeline,
    this.onQuickCreate,
    this.onCaptureMedicine,
    this.bottomContentPadding = 0,
    this.refreshRevision = 0,
    super.key,
  });

  final TodayRepository repository;
  final DateTime? now;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenReminderManager;
  final AttentionActionCallback? onOpenAttention;
  final AttentionInspectCallback? onInspectAttention;
  final ValueChanged<TimelineItem>? onOpenTimeline;
  final VoidCallback? onQuickCreate;
  final Future<void> Function()? onCaptureMedicine;
  final double bottomContentPadding;
  final int refreshRevision;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  TodaySnapshot? _snapshot;
  Object? _error;
  bool _isLoading = true;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _load(clearSnapshot: true);
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      _load();
    }
  }

  Future<void> _load({bool clearSnapshot = false}) async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        if (clearSnapshot) _snapshot = null;
      });
    }

    try {
      final snapshot = await widget.repository.load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openAttention(AttentionItem item) async {
    final callback = widget.onOpenAttention;
    if (callback == null) return;
    await callback(item);
    await _load();
  }

  Future<void> _inspectAttention(AttentionItem item) async {
    final callback = widget.onInspectAttention;
    if (callback != null) {
      await callback(item);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AttentionDetailSheet(
        item: item,
        referenceDate: widget.now ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              key: const ValueKey('today-fixed-header'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: AppPageHeader(
                eyebrow: _formatDate(now),
                title: '今天',
                largeTitle: true,
                actions: <Widget>[
                  IconButton(
                    tooltip: '管理提醒',
                    onPressed: widget.onOpenReminderManager,
                    icon: const Icon(LucideIcons.bell),
                  ),
                  IconButton(
                    tooltip: '打开设置',
                    onPressed: widget.onOpenSettings,
                    icon: const Icon(LucideIcons.settings),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('today-scroll'),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: <Widget>[
                  ..._contentSlivers(context, now: now),
                  if (widget.bottomContentPadding > 0)
                    SliverToBoxAdapter(
                      child: SizedBox(height: widget.bottomContentPadding),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _contentSlivers(BuildContext context, {required DateTime now}) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      if (_isLoading) {
        return [
          ..._quickActionSlivers(),
          ..._stateSlivers(const AppContentState.loading())
        ];
      }
      if (_error is FeatureUnavailableException) {
        return [
          ..._quickActionSlivers(),
          ..._stateSlivers(
            const AppContentState.unavailable(
              title: '今天暂时不可用',
              message: '请稍后再试',
            ),
          )
        ];
      }
      if (_error != null) {
        return [
          ..._quickActionSlivers(),
          ..._stateSlivers(
            AppContentState.error(
              title: '今天的内容加载失败',
              message: '请检查网络后重试',
              actionLabel: '重试',
              onAction: _load,
            ),
          )
        ];
      }
      return [
        ..._quickActionSlivers(),
        ..._stateSlivers(const AppContentState.loading())
      ];
    }

    final slivers = <Widget>[];
    if (snapshot.isOffline) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          sliver: const SliverToBoxAdapter(
            child: AppStatusBanner(
              severity: AppStatusSeverity.offline,
              title: '正在显示上次同步内容',
            ),
          ),
        ),
      );
    }

    final activeTimeline = _activeTimelineItems(snapshot.timeline, now: now);
    final completedTimeline =
        _completedTimelineItems(snapshot.timeline, now: now);
    if (snapshot.decisions.isEmpty &&
        activeTimeline.isEmpty &&
        completedTimeline.isEmpty) {
      slivers.addAll(_quickActionSlivers());
      slivers.addAll(
        _stateSlivers(
          const AppContentState.empty(
            title: '今天没有待处理事项',
            message: '新的提醒和计划会显示在这里',
          ),
        ),
      );
      return slivers;
    }

    final decisions = List<AttentionItem>.of(snapshot.decisions)
      ..sort((left, right) => _compareDecisionTimes(left, right, now));
    final nextDecision = decisions.firstOrNull;
    final nextTimeline = activeTimeline.firstOrNull;
    final showDecisionAsNext = nextDecision != null &&
        (nextTimeline == null ||
            !nextDecision.dueAt.isAfter(nextTimeline.scheduledAt));

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        sliver: SliverToBoxAdapter(
          child: _NextThingCard(
            decision: showDecisionAsNext ? nextDecision : null,
            timeline: showDecisionAsNext ? null : nextTimeline,
            referenceDate: now,
            onInspect: _inspectAttention,
            onOpenTimeline: widget.onOpenTimeline,
          ),
        ),
      ),
    );

    slivers.addAll(_quickActionSlivers());

    if (snapshot.decisions.isNotEmpty) {
      slivers.add(
        _sectionSliver(
          key: const ValueKey('today-decisions-section'),
          title: '现在要处理',
          child: Column(
            children: <Widget>[
              for (var index = 0; index < decisions.length; index += 1) ...[
                _DecisionRow(
                  item: decisions[index],
                  referenceDate: now,
                  position: _listRowPosition(index, decisions.length),
                  onInspect: _inspectAttention,
                  onOpen:
                      widget.onOpenAttention == null ? null : _openAttention,
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (activeTimeline.isNotEmpty) {
      slivers.add(
        _sectionSliver(
          key: const ValueKey('today-timeline-section'),
          title: '接下来',
          child: Column(
            children: <Widget>[
              for (var index = 0; index < activeTimeline.length; index += 1)
                _TimelineRow(
                  item: activeTimeline[index],
                  position: _listRowPosition(index, activeTimeline.length),
                  onOpen: widget.onOpenTimeline,
                ),
            ],
          ),
        ),
      );
    }

    if (completedTimeline.isNotEmpty) {
      slivers.add(
        _sectionSliver(
          key: const ValueKey('today-completed-section'),
          title: '已完成 · ${completedTimeline.length} 项',
          child: Column(
            children: <Widget>[
              for (var index = 0; index < completedTimeline.length; index += 1)
                _TimelineRow(
                  item: completedTimeline[index],
                  position: _listRowPosition(index, completedTimeline.length),
                  onOpen: widget.onOpenTimeline,
                ),
            ],
          ),
        ),
      );
    }

    return slivers;
  }

  List<Widget> _quickActionSlivers() {
    if (widget.onQuickCreate == null && widget.onCaptureMedicine == null) {
      return const <Widget>[];
    }
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        sliver: SliverToBoxAdapter(
          child: _QuickActions(
            onQuickCreate: widget.onQuickCreate,
            onCaptureMedicine: widget.onCaptureMedicine,
          ),
        ),
      ),
    ];
  }

  List<Widget> _stateSlivers(Widget state) {
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        sliver: SliverToBoxAdapter(child: state),
      ),
    ];
  }

  Widget _sectionSliver({
    required Key key,
    required String title,
    required Widget child,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      sliver: SliverToBoxAdapter(
        child: KeyedSubtree(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              _SoftSectionSurface(child: child),
            ],
          ),
        ),
      ),
    );
  }

  static AppListRowPosition _listRowPosition(int index, int length) {
    if (length == 1) return AppListRowPosition.single;
    if (index == 0) return AppListRowPosition.first;
    if (index == length - 1) return AppListRowPosition.last;
    return AppListRowPosition.middle;
  }

  static List<TimelineItem> _activeTimelineItems(
    List<TimelineItem> timeline, {
    required DateTime now,
  }) {
    return List<TimelineItem>.of(
      timeline.where(
        (item) =>
            _isSameLocalDate(item.scheduledAt, now) &&
            (item.status == TimelineStatus.upcoming ||
                item.status == TimelineStatus.due),
      ),
    )..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
  }

  static List<TimelineItem> _completedTimelineItems(
    List<TimelineItem> timeline, {
    required DateTime now,
  }) {
    return List<TimelineItem>.of(
      timeline.where(
        (item) =>
            _isSameLocalDate(item.scheduledAt, now) &&
            item.status == TimelineStatus.completed,
      ),
    )..sort((left, right) => right.scheduledAt.compareTo(left.scheduledAt));
  }

  static int _compareDecisionTimes(
    AttentionItem left,
    AttentionItem right,
    DateTime now,
  ) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final leftIsHistory = left.dueAt.isBefore(startOfToday);
    final rightIsHistory = right.dueAt.isBefore(startOfToday);
    if (leftIsHistory != rightIsHistory) return leftIsHistory ? 1 : -1;
    if (leftIsHistory) return right.dueAt.compareTo(left.dueAt);
    return left.dueAt.compareTo(right.dueAt);
  }
}

class _SoftSectionSurface extends StatelessWidget {
  const _SoftSectionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: child,
      ),
    );
  }
}

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({
    required this.item,
    required this.referenceDate,
    required this.position,
    this.onInspect,
    this.onOpen,
  });

  final AttentionItem item;
  final DateTime referenceDate;
  final AppListRowPosition position;
  final AttentionInspectCallback? onInspect;
  final AttentionActionCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visuals = _attentionVisuals(context, item.kind);
    final showDivider = position != AppListRowPosition.single &&
        position != AppListRowPosition.last;
    final borderRadius = switch (position) {
      AppListRowPosition.single => BorderRadius.circular(AppSpacing.radiusLg),
      AppListRowPosition.first => const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      AppListRowPosition.middle => BorderRadius.zero,
      AppListRowPosition.last => const BorderRadius.vertical(
          bottom: Radius.circular(AppSpacing.radiusLg),
        ),
    };
    final actionEnabled = onOpen != null;
    final actionSemantics = actionEnabled
        ? '${item.actionLabel}：${item.title}'
        : '${item.actionLabel}：${item.title}（未提供打开处理回调）';

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          '${visuals.label}：${item.title}，${item.reason}，${_formatDue(item.dueAt, referenceDate)}',
      child: DecoratedBox(
        key: ValueKey('today-decision-row-${item.id}'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: borderRadius,
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                )
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScaler = MediaQuery.textScalerOf(context);
                final stackedLayout =
                    constraints.maxWidth < AppSpacing.breakpointMedium ||
                        textScaler.scale(14) > 18;
                final details = _DecisionDetailTapTarget(
                  item: item,
                  borderRadius: borderRadius,
                  onInspect: onInspect,
                  child: KeyedSubtree(
                    key: ValueKey('today-decision-details-${item.id}'),
                    child: _DecisionDetails(
                      item: item,
                      visuals: visuals,
                      referenceDate: referenceDate,
                    ),
                  ),
                );
                final actions = KeyedSubtree(
                  key: ValueKey('today-decision-actions-${item.id}'),
                  child: _DecisionActions(
                    item: item,
                    enabled: actionEnabled,
                    primarySemantics: actionSemantics,
                    onOpen: onOpen,
                  ),
                );

                if (stackedLayout) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      details,
                      const SizedBox(height: AppSpacing.md),
                      actions,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(child: details),
                    const SizedBox(width: AppSpacing.sm),
                    actions,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DecisionDetailTapTarget extends StatelessWidget {
  const _DecisionDetailTapTarget({
    required this.item,
    required this.borderRadius,
    required this.child,
    this.onInspect,
  });

  final AttentionItem item;
  final BorderRadius borderRadius;
  final Widget child;
  final AttentionInspectCallback? onInspect;

  @override
  Widget build(BuildContext context) {
    final callback = onInspect;
    if (callback == null) return child;
    return Semantics(
      button: true,
      label: '查看详情：${item.title}',
      onTap: () => callback(item),
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () => callback(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: child,
        ),
      ),
    );
  }
}

class _AttentionDetailSheet extends StatelessWidget {
  const _AttentionDetailSheet({
    required this.item,
    required this.referenceDate,
  });

  final AttentionItem item;
  final DateTime referenceDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visuals = _attentionVisuals(context, item.kind);
    return SafeArea(
      key: const ValueKey('today-attention-detail-sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('提醒详情', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox.square(
                  dimension: 36,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: visuals.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(visuals.icon, color: visuals.color, size: 20),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        item.reason,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                AppStatusTag(
                  text: visuals.label,
                  color: visuals.color,
                  semanticLabel: '状态：${visuals.label}',
                ),
                Text(
                  _formatDue(item.dueAt, referenceDate),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionActions extends StatelessWidget {
  const _DecisionActions({
    required this.item,
    required this.enabled,
    required this.primarySemantics,
    required this.onOpen,
  });

  final AttentionItem item;
  final bool enabled;
  final String primarySemantics;
  final AttentionActionCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final secondaryLabel = item.secondaryActionLabel;
    final secondaryTarget = item.secondaryActionTarget;
    if (secondaryLabel == null || secondaryTarget == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: Semantics(
          container: true,
          label: primarySemantics,
          button: true,
          enabled: enabled,
          onTap: enabled ? () => onOpen!(item) : null,
          child: ExcludeSemantics(
            child: TextButton.icon(
              onPressed: enabled ? () => onOpen!(item) : null,
              iconAlignment: IconAlignment.end,
              icon: const Icon(LucideIcons.chevronRight),
              label: Text(item.actionLabel),
            ),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: enabled
                ? () => _handleSecondaryAction(context, secondaryTarget)
                : null,
            icon: const Icon(LucideIcons.clock3),
            label: Text(secondaryLabel),
          ),
        ),
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: enabled ? () => onOpen!(item) : null,
            icon: const Icon(LucideIcons.check),
            label: Text(item.actionLabel),
          ),
        ),
      ],
    );
  }

  Future<void> _handleSecondaryAction(
    BuildContext context,
    ActionTarget target,
  ) async {
    final callback = onOpen;
    if (callback == null) return;
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _SnoozeSheet(),
    );
    if (minutes == null) return;
    await callback(
      item.withAction(
        actionLabel: item.secondaryActionLabel!,
        actionTarget: target.withSnoozeMinutes(minutes),
      ),
    );
  }
}

class _SnoozeSheet extends StatelessWidget {
  const _SnoozeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('稍后提醒', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            _SnoozeOption(label: '10分钟后', minutes: 10),
            _SnoozeOption(label: '30分钟后', minutes: 30),
            _SnoozeOption(label: '明天再提醒', minutes: 1440),
          ],
        ),
      ),
    );
  }
}

class _SnoozeOption extends StatelessWidget {
  const _SnoozeOption({required this.label, required this.minutes});

  final String label;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListTile(
        leading: const Icon(LucideIcons.clock),
        title: Text(label),
        onTap: () => Navigator.of(context).pop(minutes),
      ),
    );
  }
}

class _NextThingCard extends StatelessWidget {
  const _NextThingCard({
    required this.decision,
    required this.timeline,
    required this.referenceDate,
    this.onInspect,
    this.onOpenTimeline,
  });

  final AttentionItem? decision;
  final TimelineItem? timeline;
  final DateTime referenceDate;
  final AttentionInspectCallback? onInspect;
  final ValueChanged<TimelineItem>? onOpenTimeline;

  @override
  Widget build(BuildContext context) {
    final itemTitle = decision?.title ?? timeline?.title ?? '暂无安排';
    final itemSubtitle = decision?.reason ?? timeline?.subtitle ?? '今天可以从容一点';
    final scheduledAt = decision?.dueAt ?? timeline?.scheduledAt;
    final semantic = _semanticColors(context);
    final onTap = decision != null
        ? (onInspect == null ? null : () => onInspect!(decision!))
        : timeline?.actionTarget == null || onOpenTimeline == null
            ? null
            : () => onOpenTimeline!(timeline!);

    return Semantics(
      key: const ValueKey('today-overview'),
      container: true,
      label: scheduledAt == null
          ? '下一件事：$itemTitle，$itemSubtitle'
          : '下一件事：$itemTitle，${_formatDue(scheduledAt, referenceDate)}，$itemSubtitle',
      child: ExcludeSemantics(
        child: Material(
          color: semantic.heroBackground,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    right: -58,
                    top: -48,
                    child: IgnorePointer(
                      child: Container(
                        width: 168,
                        height: 168,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                semantic.heroForeground.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 128,
                            height: 128,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: semantic.heroForeground
                                    .withValues(alpha: 0.06),
                                width: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '下一件事',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: semantic.heroForeground
                                      .withValues(alpha: 0.76),
                                ),
                      ),
                      if (scheduledAt != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _formatTime(scheduledAt),
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: semantic.heroForeground
                                        .withValues(alpha: 0.76),
                                  ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      RichText(
                        textScaler: MediaQuery.textScalerOf(context),
                        text: TextSpan(
                          text: itemTitle,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: semantic.heroForeground),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      RichText(
                        textScaler: MediaQuery.textScalerOf(context),
                        text: TextSpan(
                          text: itemSubtitle,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: semantic.heroForeground
                                        .withValues(alpha: 0.78),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({this.onQuickCreate, this.onCaptureMedicine});
  final VoidCallback? onQuickCreate;
  final Future<void> Function()? onCaptureMedicine;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (onQuickCreate != null)
          Expanded(
              child: _QuickAction(
                  key: const Key('today-quick-create-action'),
                  icon: LucideIcons.sparkles,
                  label: '快速创建',
                  onTap: onQuickCreate!)),
        if (onQuickCreate != null && onCaptureMedicine != null)
          const SizedBox(width: AppSpacing.md),
        if (onCaptureMedicine != null)
          Expanded(
              child: _QuickAction(
                  icon: LucideIcons.camera,
                  label: '拍照录入',
                  onTap: () => onCaptureMedicine!())),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 52,
      child: FilledButton.tonalIcon(
        key: key,
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        icon: Icon(icon, color: theme.colorScheme.primary),
        label: Text(label),
      ),
    );
  }
}

class _DecisionDetails extends StatelessWidget {
  const _DecisionDetails({
    required this.item,
    required this.visuals,
    required this.referenceDate,
  });

  final AttentionItem item;
  final _AttentionVisuals visuals;
  final DateTime referenceDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showReason = item.kind != AttentionKind.confirmation;
    final showStatusTag = item.kind != AttentionKind.confirmation;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Semantics(
            label: '状态：${visuals.label}',
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: 36,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: visuals.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(visuals.icon, color: visuals.color, size: 20),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(item.title, style: theme.textTheme.titleMedium),
              if (showReason) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(item.reason, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  if (showStatusTag)
                    AppStatusTag(
                      text: visuals.label,
                      color: visuals.color,
                      semanticLabel: '状态：${visuals.label}',
                    ),
                  Text(
                    _formatDue(item.dueAt, referenceDate),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, required this.position, this.onOpen});

  final TimelineItem item;
  final AppListRowPosition position;
  final ValueChanged<TimelineItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final visuals = _timelineVisuals(context, item.status);
    final onTap = item.actionTarget == null || onOpen == null
        ? null
        : () => onOpen!(item);
    return AppListRow(
      icon: visuals.icon,
      title: item.title,
      subtitle: '${_formatTime(item.scheduledAt)} · ${item.subtitle}',
      statusText: visuals.label,
      statusColor: visuals.color,
      position: position,
      onTap: onTap,
    );
  }
}

class _AttentionVisuals {
  const _AttentionVisuals({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

class _TimelineVisuals {
  const _TimelineVisuals({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

_AttentionVisuals _attentionVisuals(BuildContext context, AttentionKind kind) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = _semanticColors(context);
  return switch (kind) {
    AttentionKind.confirmation => _AttentionVisuals(
        label: '待确认',
        icon: LucideIcons.circleCheck,
        color: semantic.info,
      ),
    AttentionKind.degraded => _AttentionVisuals(
        label: '已降级',
        icon: LucideIcons.triangleAlert,
        color: semantic.warning,
      ),
    AttentionKind.permission => _AttentionVisuals(
        label: '需要授权',
        icon: LucideIcons.keyRound,
        color: scheme.error,
      ),
  };
}

_TimelineVisuals _timelineVisuals(BuildContext context, TimelineStatus status) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = _semanticColors(context);
  return switch (status) {
    TimelineStatus.upcoming => _TimelineVisuals(
        label: '即将开始',
        icon: LucideIcons.calendarClock,
        color: scheme.primary,
      ),
    TimelineStatus.due => _TimelineVisuals(
        label: '现在处理',
        icon: LucideIcons.triangleAlert,
        color: semantic.warning,
      ),
    TimelineStatus.completed => _TimelineVisuals(
        label: '已完成',
        icon: LucideIcons.circleCheck,
        color: scheme.onSurfaceVariant,
      ),
    TimelineStatus.skipped => _TimelineVisuals(
        label: '已跳过',
        icon: LucideIcons.circleMinus,
        color: scheme.onSurfaceVariant,
      ),
  };
}

AppSemanticColors _semanticColors(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<AppSemanticColors>() ??
      (theme.brightness == Brightness.dark
          ? AppSemanticColors.dark
          : AppSemanticColors.light);
}

String _formatDate(DateTime value) {
  const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${value.month}月${value.day}日 ${weekdays[value.weekday - 1]}';
}

String _formatDue(DateTime value, DateTime referenceDate) {
  if (_isSameLocalDate(value, referenceDate)) {
    return '${_formatTime(value)} 已到';
  }
  return '${value.month}月${value.day}日 ${_formatTime(value)} 已到';
}

bool _isSameLocalDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _formatTime(DateTime value) {
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.hour}:$minute';
}

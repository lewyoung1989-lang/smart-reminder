import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/data/feature_unavailable_exception.dart';
import '../../../ui/components/app_content_state.dart';
import '../../../ui/components/app_list_row.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_status_banner.dart';
import '../data/today_repository.dart';
import '../domain/today_models.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    required this.repository,
    this.now,
    this.onOpenSettings,
    this.onOpenAttention,
    this.onOpenTimeline,
    super.key,
  });

  final TodayRepository repository;
  final DateTime? now;
  final VoidCallback? onOpenSettings;
  final ValueChanged<AttentionItem>? onOpenAttention;
  final ValueChanged<TimelineItem>? onOpenTimeline;

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
    if (oldWidget.repository != widget.repository) _load(clearSnapshot: true);
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

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
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
                  eyebrow: _formatDate(now),
                  title: '今天',
                  actions: <Widget>[
                    IconButton(
                      tooltip: '打开设置',
                      onPressed: widget.onOpenSettings,
                      icon: const Icon(LucideIcons.settings),
                    ),
                  ],
                ),
              ),
            ),
            ..._contentSlivers(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _contentSlivers(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      if (_isLoading) return _stateSlivers(const AppContentState.loading());
      if (_error is FeatureUnavailableException) {
        return _stateSlivers(
          const AppContentState.unavailable(
            title: '今天暂时不可用',
            message: '请稍后再试',
          ),
        );
      }
      if (_error != null) {
        return _stateSlivers(
          AppContentState.error(
            title: '今天的内容加载失败',
            message: '请检查网络后重试',
            actionLabel: '重试',
            onAction: _load,
          ),
        );
      }
      return _stateSlivers(const AppContentState.loading());
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

    if (snapshot.decisions.isEmpty && snapshot.timeline.isEmpty) {
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

    if (snapshot.decisions.isNotEmpty) {
      final decisions = List<AttentionItem>.of(snapshot.decisions)
        ..sort((left, right) => left.dueAt.compareTo(right.dueAt));
      slivers.add(
        _sectionSliver(
          key: const ValueKey('today-decisions-section'),
          title: '需要你决定',
          child: Column(
            children: <Widget>[
              for (final item in decisions)
                _DecisionRow(
                  item: item,
                  onOpen: widget.onOpenAttention,
                ),
            ],
          ),
        ),
      );
    }

    if (snapshot.timeline.isNotEmpty) {
      final timeline = List<TimelineItem>.of(snapshot.timeline)
        ..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
      slivers.add(
        _sectionSliver(
          key: const ValueKey('today-timeline-section'),
          title: '接下来',
          child: Column(
            children: <Widget>[
              for (var index = 0; index < timeline.length; index += 1)
                _TimelineRow(
                  item: timeline[index],
                  position: _listRowPosition(index, timeline.length),
                  onOpen: widget.onOpenTimeline,
                ),
            ],
          ),
        ),
      );
    }

    return slivers;
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
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              child,
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
}

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({required this.item, this.onOpen});

  final AttentionItem item;
  final ValueChanged<AttentionItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visuals = _attentionVisuals(context, item.kind);
    final enabled = onOpen != null;
    final actionSemantics = enabled
        ? '${item.actionLabel}：${item.title}'
        : '${item.actionLabel}：${item.title}（未提供打开处理回调）';

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          '${visuals.label}：${item.title}，${item.reason}，${_formatDue(item.dueAt)}',
      child: DecoratedBox(
        key: ValueKey('today-decision-row-${item.id}'),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
          borderRadius: BorderRadius.zero,
        ),
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg + 4,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < AppSpacing.breakpointMedium ||
                          MediaQuery.textScalerOf(context).scale(14) > 20;
                  final details =
                      _DecisionDetails(item: item, visuals: visuals);
                  final action = Semantics(
                    container: true,
                    label: actionSemantics,
                    button: true,
                    enabled: enabled,
                    onTap: enabled ? () => onOpen!(item) : null,
                    child: ExcludeSemantics(
                      child: FilledButton(
                        onPressed: enabled ? () => onOpen!(item) : null,
                        child: Text(item.actionLabel),
                      ),
                    ),
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        details,
                        const SizedBox(height: AppSpacing.lg),
                        action,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: details),
                      const SizedBox(width: AppSpacing.lg),
                      action,
                    ],
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: 4,
              child: ColoredBox(color: visuals.color),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionDetails extends StatelessWidget {
  const _DecisionDetails({required this.item, required this.visuals});

  final AttentionItem item;
  final _AttentionVisuals visuals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          label: '状态：${visuals.label}',
          child: ExcludeSemantics(
            child: Icon(visuals.icon, color: visuals.color, size: 22),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(item.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(item.reason, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  Text(
                    visuals.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: visuals.color,
                    ),
                  ),
                  Text(
                    _formatDue(item.dueAt),
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
    return AppListRow(
      icon: visuals.icon,
      title: item.title,
      subtitle: '${_formatTime(item.scheduledAt)} · ${item.subtitle}',
      statusText: visuals.label,
      statusColor: visuals.color,
      position: position,
      onTap: onOpen == null ? null : () => onOpen!(item),
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

String _formatDue(DateTime value) => '${_formatTime(value)} 截止';

String _formatTime(DateTime value) {
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.hour}:$minute';
}

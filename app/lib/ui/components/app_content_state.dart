import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_spacing.dart';

enum _ContentStateKind { loading, empty, error, unavailable }

class AppContentState extends StatelessWidget {
  const AppContentState.loading({super.key})
      : _kind = _ContentStateKind.loading,
        title = null,
        message = null,
        actionLabel = null,
        onAction = null;

  const AppContentState.empty({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  })  : assert(
          (actionLabel == null) == (onAction == null),
          'actionLabel and onAction must be supplied together.',
        ),
        _kind = _ContentStateKind.empty;

  const AppContentState.error({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  })  : assert(
          (actionLabel == null) == (onAction == null),
          'actionLabel and onAction must be supplied together.',
        ),
        _kind = _ContentStateKind.error;

  const AppContentState.unavailable({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  })  : assert(
          (actionLabel == null) == (onAction == null),
          'actionLabel and onAction must be supplied together.',
        ),
        _kind = _ContentStateKind.unavailable;

  final _ContentStateKind _kind;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (_kind == _ContentStateKind.loading) {
      return const _LoadingState(key: ValueKey('app-content-state-loading'));
    }

    final visuals = switch (_kind) {
      _ContentStateKind.empty => const (
          key: ValueKey('app-content-state-empty'),
          icon: LucideIcons.inbox,
        ),
      _ContentStateKind.error => const (
          key: ValueKey('app-content-state-error'),
          icon: LucideIcons.triangleAlert,
        ),
      _ContentStateKind.unavailable => const (
          key: ValueKey('app-content-state-unavailable'),
          icon: LucideIcons.cloudOff,
        ),
      _ContentStateKind.loading => throw StateError('Handled above'),
    };

    return _MessageState(
      key: visuals.key,
      icon: visuals.icon,
      title: title!,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: '正在加载',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < 4; index += 1) ...[
            SizedBox(
              key: ValueKey('app-content-skeleton-$index'),
              height: 64,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: index < 3
                      ? Border(
                          bottom: BorderSide(
                            color: scheme.outlineVariant,
                            width: 0.5,
                          ),
                        )
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 32,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: 0.62,
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSm,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            FractionallySizedBox(
                              widthFactor: 0.38,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSm,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: scheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

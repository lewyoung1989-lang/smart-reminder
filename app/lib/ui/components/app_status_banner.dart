import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

enum AppStatusSeverity { info, success, warning, error, offline }

class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner({
    super.key,
    required this.severity,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  }) : assert(
          (actionLabel == null) == (onAction == null),
          'actionLabel and onAction must be supplied together.',
        );

  final AppStatusSeverity severity;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visuals = _visualsFor(theme, severity);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${visuals.semanticPrefix}：$title',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visuals.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  visuals.icon,
                  color: visuals.foreground,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        message!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static _StatusVisuals _visualsFor(
    ThemeData theme,
    AppStatusSeverity severity,
  ) {
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final scheme = theme.colorScheme;

    return switch (severity) {
      AppStatusSeverity.info => _StatusVisuals(
          semanticPrefix: '信息',
          icon: LucideIcons.info,
          foreground: semantic.info,
          surface: semantic.infoSurface,
        ),
      AppStatusSeverity.success => _StatusVisuals(
          semanticPrefix: '成功',
          icon: LucideIcons.circleCheck,
          foreground: semantic.success,
          surface: semantic.success.withValues(alpha: 0.12),
        ),
      AppStatusSeverity.warning => _StatusVisuals(
          semanticPrefix: '警告',
          icon: LucideIcons.triangleAlert,
          foreground: semantic.warning,
          surface: semantic.warningSurface,
        ),
      AppStatusSeverity.error => _StatusVisuals(
          semanticPrefix: '错误',
          icon: LucideIcons.circleX,
          foreground: scheme.error,
          surface: scheme.errorContainer,
        ),
      AppStatusSeverity.offline => _StatusVisuals(
          semanticPrefix: '离线',
          icon: LucideIcons.cloudOff,
          foreground: scheme.onSurfaceVariant,
          surface: scheme.surfaceContainer,
        ),
    };
  }
}

class _StatusVisuals {
  const _StatusVisuals({
    required this.semanticPrefix,
    required this.icon,
    required this.foreground,
    required this.surface,
  });

  final String semanticPrefix;
  final IconData icon;
  final Color foreground;
  final Color surface;
}

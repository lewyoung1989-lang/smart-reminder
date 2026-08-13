import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

enum AppListRowPosition { single, first, middle, last }

class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.statusText,
    this.statusColor,
    this.onTap,
    this.position = AppListRowPosition.single,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? statusText;
  final Color? statusColor;
  final VoidCallback? onTap;
  final AppListRowPosition position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showDivider = position != AppListRowPosition.single &&
        position != AppListRowPosition.last;
    final semanticsLabel = [
      title,
      subtitle,
      if (statusText != null) statusText!,
    ].join('，');

    return Semantics(
      container: true,
      button: onTap != null,
      enabled: onTap != null ? true : null,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textScaler = MediaQuery.textScalerOf(context);
                    final useCompactLayout =
                        constraints.maxWidth < AppSpacing.breakpointMedium ||
                            textScaler.scale(14) > 20;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Icon(icon, size: 22, color: scheme.primary),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Container(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            decoration: BoxDecoration(
                              border: showDivider
                                  ? Border(
                                      bottom: BorderSide(
                                        color: scheme.outlineVariant,
                                        width: 0.5,
                                      ),
                                    )
                                  : null,
                            ),
                            child: _RowText(
                              title: title,
                              subtitle: subtitle,
                              compactStatus:
                                  useCompactLayout ? statusText : null,
                              statusColor: statusColor,
                            ),
                          ),
                        ),
                        if (!useCompactLayout && statusText != null) ...[
                          const SizedBox(width: AppSpacing.lg),
                          _StatusText(text: statusText!, color: statusColor),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({
    required this.title,
    required this.subtitle,
    required this.compactStatus,
    required this.statusColor,
  });

  final String title;
  final String subtitle;
  final String? compactStatus;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: theme.textTheme.bodySmall),
        if (compactStatus != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _StatusText(text: compactStatus!, color: statusColor),
        ],
      ],
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.onSurfaceVariant;

    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(color: foreground),
    );
  }
}

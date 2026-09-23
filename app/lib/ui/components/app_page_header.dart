import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.largeTitle = false,
    this.actions = const [],
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final bool largeTitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: largeTitle
                      ? theme.textTheme.displaySmall
                      : theme.textTheme.titleLarge,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.lg),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < actions.length; index += 1) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Center(child: actions[index]),
                ),
                if (index < actions.length - 1)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

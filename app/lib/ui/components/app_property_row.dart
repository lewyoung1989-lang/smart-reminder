import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

class AppPropertyRow extends StatelessWidget {
  const AppPropertyRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 480;
        final labelWidget = Text(label, style: theme.textTheme.labelMedium);
        final valueWidget = DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium,
          softWrap: true,
          overflow: TextOverflow.visible,
          child: value,
        );

        if (!horizontal) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              labelWidget,
              const SizedBox(height: AppSpacing.sm),
              valueWidget,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 200, child: labelWidget),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: valueWidget),
          ],
        );
      },
    );
  }
}

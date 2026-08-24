import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.count});

  final T value;
  final String label;
  final int? count;
}

class AppSegmentedControl<T> extends StatelessWidget {
  static const double _controlHeight = 44;

  AppSegmentedControl({
    super.key,
    required this.value,
    required List<AppSegment<T>> options,
    required this.onChanged,
  }) : options = _validatedOptions(value, options);

  final T value;
  final List<AppSegment<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final controlHeight = textScaler.scale(14) + 22 < _controlHeight
        ? _controlHeight
        : textScaler.scale(14) + 22;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: SizedBox(
        height: controlHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minimumOptionWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth / options.length
                : 112.0;
            var minimumLabelWidth = 0.0;
            for (final option in options) {
              final painter = TextPainter(
                text: TextSpan(
                  text: option.count == null
                      ? option.label
                      : '${option.label} ${option.count}',
                  style: labelStyle,
                ),
                textDirection: Directionality.of(context),
                textScaler: textScaler,
                maxLines: 1,
              )..layout();
              if (painter.width > minimumLabelWidth) {
                minimumLabelWidth = painter.width;
              }
            }

            final selectedIndex =
                options.indexWhere((option) => option.value == value);
            final contentOptionWidth = minimumLabelWidth + 24;
            final optionWidth = minimumOptionWidth > contentOptionWidth
                ? minimumOptionWidth
                : contentOptionWidth;
            final contentWidth = optionWidth * options.length;
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: contentWidth,
                  height: controlHeight,
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        key: const ValueKey(
                          'app-segmented-control-indicator',
                        ),
                        duration: disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        left: selectedIndex * optionWidth + 3,
                        top: 3,
                        width: optionWidth - 6,
                        bottom: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.shadow
                                    .withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final option in options)
                            SizedBox(
                              width: optionWidth,
                              height: controlHeight,
                              child: _SegmentOption<T>(
                                option: option,
                                selected: option.value == value,
                                onChanged: onChanged,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static List<AppSegment<S>> _validatedOptions<S>(
    S value,
    List<AppSegment<S>> options,
  ) {
    if (options.length < 2) {
      throw ArgumentError.value(
        options,
        'options',
        'must contain at least two options',
      );
    }
    var matches = 0;
    for (final option in options) {
      if (option.value == value) matches += 1;
    }
    if (matches != 1) {
      throw ArgumentError.value(
        value,
        'value',
        'must match exactly one option; found $matches matches',
      );
    }
    for (var left = 0; left < options.length; left += 1) {
      for (var right = left + 1; right < options.length; right += 1) {
        if (options[left].value == options[right].value) {
          throw ArgumentError.value(
            options[right].value,
            'options',
            'contains duplicate option value at indexes $left and $right',
          );
        }
      }
    }
    return options;
  }
}

class _SegmentOption<T> extends StatelessWidget {
  const _SegmentOption({
    required this.option,
    required this.selected,
    required this.onChanged,
  });

  final AppSegment<T> option;
  final bool selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: () => onChanged(option.value),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  option.label,
                  softWrap: false,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (option.count != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${option.count}',
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

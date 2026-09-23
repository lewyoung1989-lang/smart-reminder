import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.count});

  final T value;
  final String label;
  final int? count;
}

enum AppSegmentedControlStyle { capsules, tabs, compactTabs }

class AppSegmentedControl<T> extends StatelessWidget {
  static const double _controlHeight = 44;

  AppSegmentedControl({
    super.key,
    required this.value,
    required List<AppSegment<T>> options,
    required this.onChanged,
    this.style = AppSegmentedControlStyle.capsules,
  }) : options = _validatedOptions(value, options);

  final T value;
  final List<AppSegment<T>> options;
  final ValueChanged<T> onChanged;
  final AppSegmentedControlStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final isCapsule = style == AppSegmentedControlStyle.capsules;
    final labelBase = switch (style) {
      AppSegmentedControlStyle.capsules => theme.textTheme.labelMedium,
      AppSegmentedControlStyle.tabs => theme.textTheme.titleSmall,
      AppSegmentedControlStyle.compactTabs => theme.textTheme.labelLarge,
    };
    final labelStyle = labelBase?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final scaledLabelHeight = textScaler.scale(labelBase?.fontSize ?? 14);
    final controlHeight = scaledLabelHeight + 22 < _controlHeight
        ? _controlHeight
        : scaledLabelHeight + 22;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      height: isCapsule ? controlHeight : controlHeight + 2,
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
          return SingleChildScrollView(
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
                    left: isCapsule
                        ? selectedIndex * optionWidth + 3
                        : selectedIndex * optionWidth,
                    top: isCapsule ? 4 : null,
                    width: isCapsule ? optionWidth - 6 : optionWidth,
                    bottom: isCapsule ? 4 : 0,
                    height: isCapsule ? null : 2,
                    child: isCapsule
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          )
                        : Align(
                            alignment: Alignment.bottomCenter,
                            child: SizedBox(
                              width:
                                  style == AppSegmentedControlStyle.compactTabs
                                      ? 28
                                      : 36,
                              height: 2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
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
                            style: style,
                            onChanged: onChanged,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
    required this.style,
    required this.onChanged,
  });

  final AppSegment<T> option;
  final bool selected;
  final AppSegmentedControlStyle style;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCapsule = style == AppSegmentedControlStyle.capsules;
    final labelStyle = switch (style) {
      AppSegmentedControlStyle.capsules => theme.textTheme.labelMedium,
      AppSegmentedControlStyle.tabs => theme.textTheme.titleSmall,
      AppSegmentedControlStyle.compactTabs => theme.textTheme.labelLarge,
    };
    final foreground = selected
        ? (isCapsule ? theme.colorScheme.onPrimary : theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(isCapsule ? 999 : 8),
          onTap: () => onChanged(option.value),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  option.label,
                  softWrap: false,
                  style: labelStyle?.copyWith(
                    color: foreground,
                    fontWeight: selected
                        ? (isCapsule ? FontWeight.w600 : FontWeight.w700)
                        : FontWeight.w500,
                  ),
                ),
                if (option.count != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${option.count}',
                    softWrap: false,
                    style: labelStyle?.copyWith(
                      color: foreground,
                      fontWeight: selected
                          ? (isCapsule ? FontWeight.w600 : FontWeight.w700)
                          : FontWeight.w500,
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

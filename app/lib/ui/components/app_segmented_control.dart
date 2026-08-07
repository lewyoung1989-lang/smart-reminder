import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_spacing.dart';

class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.count});

  final T value;
  final String label;
  final int? count;
}

class AppSegmentedControl<T> extends StatelessWidget {
  static const double _controlHeight = 44;
  static const double _visualTrackHeight = 40;

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
    final scheme = theme.colorScheme;
    const visualTrackInset = (_controlHeight - _visualTrackHeight) / 2;

    return SizedBox(
      height: _controlHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumOptionWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth / options.length
              : 112.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                top: visualTrackInset,
                bottom: visualTrackInset,
                child: DecoratedBox(
                  key: const ValueKey(
                    'app-segmented-control-visual-track',
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRect(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final option in options)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: minimumOptionWidth,
                            ),
                            child: _SegmentOption<T>(
                              option: option,
                              selected: option.value == value,
                              onChanged: onChanged,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
      if (option.value == value) {
        matches += 1;
      }
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
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(option.value),
          child: SizedBox(
            height: AppSegmentedControl._controlHeight,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: SizedBox(
                  height: AppSegmentedControl._visualTrackHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 16,
                          child: selected
                              ? Icon(
                                  LucideIcons.check,
                                  size: 16,
                                  color: foreground,
                                )
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          option.label,
                          softWrap: false,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                        if (option.count != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            '${option.count}',
                            softWrap: false,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: foreground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

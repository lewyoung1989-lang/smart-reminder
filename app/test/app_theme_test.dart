import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_colors.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses the approved design tokens', () {
      final theme = AppTheme.light();
      final semanticColors = theme.extension<AppSemanticColors>();

      expect(theme.colorScheme.primary, const Color(0xFF173E31));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F9F8));
      expect(semanticColors?.warning, const Color(0xFF9A6700));
      expect(theme.cardTheme.elevation, 0);
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.textTheme.bodyMedium?.letterSpacing, 0);
      expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
    });

    test('dark theme uses the approved design tokens', () {
      final theme = AppTheme.dark();
      final semanticColors = theme.extension<AppSemanticColors>();

      expect(theme.scaffoldBackgroundColor, const Color(0xFF0F1512));
      expect(theme.colorScheme.surface, const Color(0xFF171E1A));
      expect(theme.colorScheme.primary, const Color(0xFF76D3AC));
      expect(semanticColors?.warning, const Color(0xFFFFC95C));
      expect(theme.cardTheme.elevation, 0);
    });

    for (final entry in <String, ThemeData Function()>{
      'light': AppTheme.light,
      'dark': AppTheme.dark,
    }.entries) {
      test('${entry.key} theme uses accessible disabled button colors', () {
        final theme = entry.value();
        final scheme = theme.colorScheme;
        final enabled = <WidgetState>{};
        final disabled = <WidgetState>{WidgetState.disabled};
        final disabledBackground = scheme.onSurface.withValues(alpha: 0.12);
        final disabledForeground = scheme.onSurface.withValues(alpha: 0.38);
        final filledStyle = theme.filledButtonTheme.style!;
        final outlinedStyle = theme.outlinedButtonTheme.style!;
        final iconStyle = theme.iconButtonTheme.style!;

        expect(filledStyle.backgroundColor?.resolve(enabled), scheme.primary);
        expect(filledStyle.foregroundColor?.resolve(enabled), scheme.onPrimary);
        expect(
          filledStyle.backgroundColor?.resolve(disabled),
          disabledBackground,
        );
        expect(
          filledStyle.foregroundColor?.resolve(disabled),
          disabledForeground,
        );
        expect(outlinedStyle.foregroundColor?.resolve(enabled), scheme.primary);
        expect(
          outlinedStyle.foregroundColor?.resolve(disabled),
          disabledForeground,
        );
        expect(outlinedStyle.side?.resolve(enabled)?.color, scheme.outline);
        expect(
          outlinedStyle.side?.resolve(disabled)?.color,
          disabledBackground,
        );
        expect(iconStyle.foregroundColor?.resolve(enabled), scheme.onSurface);
        expect(
          iconStyle.foregroundColor?.resolve(disabled),
          disabledForeground,
        );
      });

      test('${entry.key} theme has zero tracking for every text style', () {
        final textTheme = entry.value().textTheme;
        final styles = <String, TextStyle?>{
          'displayLarge': textTheme.displayLarge,
          'displayMedium': textTheme.displayMedium,
          'displaySmall': textTheme.displaySmall,
          'headlineLarge': textTheme.headlineLarge,
          'headlineMedium': textTheme.headlineMedium,
          'headlineSmall': textTheme.headlineSmall,
          'titleLarge': textTheme.titleLarge,
          'titleMedium': textTheme.titleMedium,
          'titleSmall': textTheme.titleSmall,
          'bodyLarge': textTheme.bodyLarge,
          'bodyMedium': textTheme.bodyMedium,
          'bodySmall': textTheme.bodySmall,
          'labelLarge': textTheme.labelLarge,
          'labelMedium': textTheme.labelMedium,
          'labelSmall': textTheme.labelSmall,
        };

        for (final style in styles.entries) {
          expect(style.value, isNotNull, reason: style.key);
          expect(style.value?.letterSpacing, 0, reason: style.key);
        }
      });

      test('${entry.key} theme preserves the approved typography', () {
        final textTheme = entry.value().textTheme;
        final approvedStyles = <(TextStyle?, (double, double, FontWeight))>[
          (textTheme.displaySmall, (28, 36, FontWeight.w700)),
          (textTheme.headlineSmall, (22, 30, FontWeight.w700)),
          (textTheme.titleLarge, (18, 26, FontWeight.w600)),
          (textTheme.titleMedium, (16, 24, FontWeight.w600)),
          (textTheme.bodyLarge, (16, 24, FontWeight.w400)),
          (textTheme.bodyMedium, (14, 21, FontWeight.w400)),
          (textTheme.labelLarge, (14, 20, FontWeight.w600)),
          (textTheme.labelSmall, (12, 18, FontWeight.w500)),
        ];

        for (final (style, specification) in approvedStyles) {
          final (fontSize, lineHeight, fontWeight) = specification;
          expect(style?.fontSize, fontSize);
          expect(style?.height, closeTo(lineHeight / fontSize, 0.000001));
          expect(style?.fontWeight, fontWeight);
        }
      });

      test('${entry.key} theme keeps button tap targets at least 44dp', () {
        final theme = entry.value();
        final styles = <ButtonStyle>[
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.iconButtonTheme.style!,
        ];

        for (final style in styles) {
          expect(style.minimumSize?.resolve(<WidgetState>{})?.height, 44);
          expect(
            style.minimumSize
                ?.resolve(<WidgetState>{WidgetState.disabled})?.height,
            44,
          );
        }
      });
    }

    test('light theme uses a stronger input boundary', () {
      final border = AppTheme.light().inputDecorationTheme.enabledBorder;

      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderSide.color,
        const Color(0xFF65716B),
      );
    });

    test('dark theme uses a stronger input boundary', () {
      final border = AppTheme.dark().inputDecorationTheme.enabledBorder;

      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderSide.color,
        const Color(0xFFAAB6AF),
      );
    });
  });
}

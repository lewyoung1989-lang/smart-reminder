import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_colors.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses the approved design tokens', () {
      final theme = AppTheme.light();
      final semanticColors = theme.extension<AppSemanticColors>();

      expect(theme.colorScheme.primary, const Color(0xFF087759));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F7F4));
      expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(semanticColors?.warning, const Color(0xFF8D6508));
      expect(theme.cardTheme.elevation, 1);
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.textTheme.bodyMedium?.letterSpacing, 0);
      expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
    });

    test('dark theme uses the approved design tokens', () {
      final theme = AppTheme.dark();
      final semanticColors = theme.extension<AppSemanticColors>();

      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(theme.colorScheme.surface, const Color(0xFF1C1C1E));
      expect(theme.colorScheme.primary, const Color(0xFF78D5B2));
      expect(semanticColors?.warning, const Color(0xFFFFC95C));
      expect(theme.cardTheme.elevation, 1);
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
          (textTheme.displaySmall, (36, 44, FontWeight.w700)),
          (textTheme.headlineSmall, (22, 28, FontWeight.w600)),
          (textTheme.titleLarge, (20, 26, FontWeight.w700)),
          (textTheme.titleMedium, (17, 22, FontWeight.w600)),
          (textTheme.bodyLarge, (17, 22, FontWeight.w400)),
          (textTheme.bodyMedium, (15, 20, FontWeight.w400)),
          (textTheme.labelLarge, (15, 20, FontWeight.w600)),
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
        expect(
          theme.filledButtonTheme.style?.shape?.resolve(<WidgetState>{}),
          isA<RoundedRectangleBorder>(),
        );
        expect(
          theme.outlinedButtonTheme.style?.shape?.resolve(<WidgetState>{}),
          isA<RoundedRectangleBorder>(),
        );
        expect(
          theme.iconButtonTheme.style?.shape?.resolve(<WidgetState>{}),
          isA<CircleBorder>(),
        );
      });
    }

    test('light theme uses a native filled input without a resting border', () {
      final border = AppTheme.light().inputDecorationTheme.enabledBorder;

      expect(border, isA<OutlineInputBorder>());
      expect((border! as OutlineInputBorder).borderSide, BorderSide.none);
      expect(AppTheme.light().inputDecorationTheme.fillColor,
          const Color(0xFFE4ECE7));
    });

    test('dark theme uses a native filled input without a resting border', () {
      final border = AppTheme.dark().inputDecorationTheme.enabledBorder;

      expect(border, isA<OutlineInputBorder>());
      expect((border! as OutlineInputBorder).borderSide, BorderSide.none);
      expect(AppTheme.dark().inputDecorationTheme.fillColor,
          const Color(0xFF2C2C2E));
    });
  });
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

abstract final class AppTheme {
  static const fontFamily = 'NotoSansSC';

  static ThemeData light() {
    const background = Color(0xFFF7F9F8);
    const surface = Color(0xFFFFFFFF);
    const surfaceMuted = Color(0xFFEEF2F0);
    const primary = Color(0xFF173E31);
    const onPrimary = Color(0xFFFFFFFF);
    const textPrimary = Color(0xFF18211D);
    const textSecondary = Color(0xFF65716B);
    const outline = Color(0xFFCDD6D1);
    const error = Color(0xFFB3261E);
    const errorSurface = Color(0xFFFCE8E6);

    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: surfaceMuted,
      onPrimaryContainer: textPrimary,
      primaryFixed: surfaceMuted,
      primaryFixedDim: outline,
      onPrimaryFixed: primary,
      onPrimaryFixedVariant: textSecondary,
      secondary: Color(0xFF286A9B),
      onSecondary: onPrimary,
      secondaryContainer: Color(0xFFE7F1FA),
      onSecondaryContainer: textPrimary,
      secondaryFixed: Color(0xFFE7F1FA),
      secondaryFixedDim: Color(0xFFBDD8EC),
      onSecondaryFixed: Color(0xFF173247),
      onSecondaryFixedVariant: Color(0xFF286A9B),
      tertiary: Color(0xFF278564),
      onTertiary: onPrimary,
      tertiaryContainer: surfaceMuted,
      onTertiaryContainer: textPrimary,
      tertiaryFixed: surfaceMuted,
      tertiaryFixedDim: outline,
      onTertiaryFixed: primary,
      onTertiaryFixedVariant: Color(0xFF278564),
      error: error,
      onError: onPrimary,
      errorContainer: errorSurface,
      onErrorContainer: error,
      surface: surface,
      onSurface: textPrimary,
      surfaceDim: background,
      surfaceBright: surface,
      surfaceContainerLowest: surface,
      surfaceContainerLow: background,
      surfaceContainer: surfaceMuted,
      surfaceContainerHigh: surfaceMuted,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: textSecondary,
      outline: outline,
      outlineVariant: outline,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: textPrimary,
      onInverseSurface: background,
      inversePrimary: Color(0xFF76D3AC),
      surfaceTint: Colors.transparent,
    );

    return _build(
      colorScheme: colorScheme,
      scaffoldBackground: background,
      surfaceMuted: surfaceMuted,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      semanticColors: AppSemanticColors.light,
    );
  }

  static ThemeData dark() {
    const background = Color(0xFF0F1512);
    const surface = Color(0xFF171E1A);
    const surfaceMuted = Color(0xFF202923);
    const primary = Color(0xFF76D3AC);
    const onPrimary = Color(0xFF0B2A20);
    const textPrimary = Color(0xFFE7EEE9);
    const textSecondary = Color(0xFFAAB6AF);
    const outline = Color(0xFF3D4943);

    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: surfaceMuted,
      onPrimaryContainer: textPrimary,
      primaryFixed: primary,
      primaryFixedDim: Color(0xFF4EAA86),
      onPrimaryFixed: onPrimary,
      onPrimaryFixedVariant: Color(0xFF173E31),
      secondary: Color(0xFF93C9F2),
      onSecondary: onPrimary,
      secondaryContainer: Color(0xFF173247),
      onSecondaryContainer: textPrimary,
      secondaryFixed: Color(0xFFE7F1FA),
      secondaryFixedDim: Color(0xFF93C9F2),
      onSecondaryFixed: Color(0xFF173247),
      onSecondaryFixedVariant: Color(0xFF286A9B),
      tertiary: primary,
      onTertiary: onPrimary,
      tertiaryContainer: surfaceMuted,
      onTertiaryContainer: textPrimary,
      tertiaryFixed: primary,
      tertiaryFixedDim: Color(0xFF4EAA86),
      onTertiaryFixed: onPrimary,
      onTertiaryFixedVariant: Color(0xFF173E31),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: surface,
      onSurface: textPrimary,
      surfaceDim: background,
      surfaceBright: surfaceMuted,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceMuted,
      surfaceContainerHigh: surfaceMuted,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: textSecondary,
      outline: outline,
      outlineVariant: outline,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: textPrimary,
      onInverseSurface: background,
      inversePrimary: Color(0xFF173E31),
      surfaceTint: Colors.transparent,
    );

    return _build(
      colorScheme: colorScheme,
      scaffoldBackground: background,
      surfaceMuted: surfaceMuted,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      semanticColors: AppSemanticColors.dark,
    );
  }

  static ThemeData _build({
    required ColorScheme colorScheme,
    required Color scaffoldBackground,
    required Color surfaceMuted,
    required Color textPrimary,
    required Color textSecondary,
    required AppSemanticColors semanticColors,
  }) {
    final textTheme = TextTheme(
      displayLarge: _textStyle(40, 48, FontWeight.w700, textPrimary),
      displayMedium: _textStyle(34, 42, FontWeight.w700, textPrimary),
      displaySmall: _textStyle(28, 36, FontWeight.w700, textPrimary),
      headlineLarge: _textStyle(26, 34, FontWeight.w700, textPrimary),
      headlineMedium: _textStyle(24, 32, FontWeight.w700, textPrimary),
      headlineSmall: _textStyle(22, 30, FontWeight.w700, textPrimary),
      titleLarge: _textStyle(18, 26, FontWeight.w600, textPrimary),
      titleMedium: _textStyle(16, 24, FontWeight.w600, textPrimary),
      titleSmall: _textStyle(14, 20, FontWeight.w600, textPrimary),
      bodyLarge: _textStyle(16, 24, FontWeight.w400, textPrimary),
      bodyMedium: _textStyle(14, 21, FontWeight.w400, textPrimary),
      bodySmall: _textStyle(12, 18, FontWeight.w400, textSecondary),
      labelLarge: _textStyle(14, 20, FontWeight.w600, textPrimary),
      labelMedium: _textStyle(12, 18, FontWeight.w600, textSecondary),
      labelSmall: _textStyle(12, 18, FontWeight.w500, textSecondary),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide(color: textSecondary),
    );
    final componentShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    );
    final indicatorShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    );
    final disabledBackground = colorScheme.onSurface.withValues(alpha: 0.12);
    final disabledForeground = colorScheme.onSurface.withValues(alpha: 0.38);

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: fontFamily,
      textTheme: textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[semanticColors],
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          backgroundColor: _stateColor(
            enabled: colorScheme.primary,
            disabled: disabledBackground,
          ),
          foregroundColor: _stateColor(
            enabled: colorScheme.onPrimary,
            disabled: disabledForeground,
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          foregroundColor: _stateColor(
            enabled: colorScheme.primary,
            disabled: disabledForeground,
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? disabledBackground
                  : colorScheme.outline,
            );
          }),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.square(44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
          foregroundColor: _stateColor(
            enabled: colorScheme.onSurface,
            disabled: disabledForeground,
          ),
          shape: WidgetStatePropertyAll(componentShape),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: surfaceMuted,
        indicatorShape: indicatorShape,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: isSelected ? colorScheme.primary : textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? colorScheme.primary : textSecondary,
            size: 24,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: textSecondary,
        ),
        selectedIconTheme: IconThemeData(color: colorScheme.primary, size: 24),
        unselectedIconTheme: IconThemeData(color: textSecondary, size: 24),
        useIndicator: true,
        indicatorColor: surfaceMuted,
        indicatorShape: indicatorShape,
        minWidth: 72,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        modalElevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: colorScheme.outline,
        dragHandleSize: const Size(32, 4),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline,
        space: 1,
        thickness: 1,
      ),
    );
  }

  static TextStyle _textStyle(
    double fontSize,
    double lineHeight,
    FontWeight fontWeight,
    Color color,
  ) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: lineHeight / fontSize,
      fontWeight: fontWeight,
      letterSpacing: 0,
      color: color,
    );
  }

  static WidgetStateProperty<Color> _stateColor({
    required Color enabled,
    required Color disabled,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.disabled) ? disabled : enabled;
    });
  }
}

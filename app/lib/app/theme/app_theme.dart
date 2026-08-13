import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

abstract final class AppTheme {
  static const fontFamily = 'PingFang SC';

  static ThemeData light() {
    const background = Color(0xFFF2F2F7);
    const surface = Color(0xFFFFFFFF);
    const surfaceMuted = Color(0xFFE5E5EA);
    const primary = Color(0xFF176B52);
    const onPrimary = Color(0xFFFFFFFF);
    const textPrimary = Color(0xFF1C1C1E);
    const textSecondary = Color(0xFF6C6C70);
    const outline = Color(0xFFC6C6C8);
    const error = Color(0xFFB42318);
    const errorSurface = Color(0xFFFFE9E7);

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
      secondary: primary,
      onSecondary: onPrimary,
      secondaryContainer: surfaceMuted,
      onSecondaryContainer: textPrimary,
      secondaryFixed: surfaceMuted,
      secondaryFixedDim: outline,
      onSecondaryFixed: primary,
      onSecondaryFixedVariant: textSecondary,
      tertiary: primary,
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
      inversePrimary: Color(0xFF78D5B2),
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
    const background = Color(0xFF000000);
    const surface = Color(0xFF1C1C1E);
    const surfaceMuted = Color(0xFF2C2C2E);
    const primary = Color(0xFF78D5B2);
    const onPrimary = Color(0xFF092A20);
    const textPrimary = Color(0xFFF2F2F7);
    const textSecondary = Color(0xFFAEAEB2);
    const outline = Color(0xFF3A3A3C);

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
      secondary: primary,
      onSecondary: onPrimary,
      secondaryContainer: surfaceMuted,
      onSecondaryContainer: textPrimary,
      secondaryFixed: primary,
      secondaryFixedDim: Color(0xFF4EAA86),
      onSecondaryFixed: onPrimary,
      onSecondaryFixedVariant: Color(0xFF173E31),
      tertiary: primary,
      onTertiary: onPrimary,
      tertiaryContainer: surfaceMuted,
      onTertiaryContainer: textPrimary,
      tertiaryFixed: primary,
      tertiaryFixedDim: Color(0xFF4EAA86),
      onTertiaryFixed: onPrimary,
      onTertiaryFixedVariant: Color(0xFF173E31),
      error: Color(0xFFFF6961),
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
      displayLarge: _textStyle(40, 48, FontWeight.w600, textPrimary),
      displayMedium: _textStyle(34, 42, FontWeight.w600, textPrimary),
      displaySmall: _textStyle(32, 40, FontWeight.w600, textPrimary),
      headlineLarge: _textStyle(28, 34, FontWeight.w600, textPrimary),
      headlineMedium: _textStyle(24, 30, FontWeight.w600, textPrimary),
      headlineSmall: _textStyle(22, 28, FontWeight.w600, textPrimary),
      titleLarge: _textStyle(20, 25, FontWeight.w600, textPrimary),
      titleMedium: _textStyle(17, 22, FontWeight.w600, textPrimary),
      titleSmall: _textStyle(16, 21, FontWeight.w600, textPrimary),
      bodyLarge: _textStyle(17, 22, FontWeight.w400, textPrimary),
      bodyMedium: _textStyle(15, 20, FontWeight.w400, textPrimary),
      bodySmall: _textStyle(13, 18, FontWeight.w400, textSecondary),
      labelLarge: _textStyle(15, 20, FontWeight.w600, textPrimary),
      labelMedium: _textStyle(13, 18, FontWeight.w600, textSecondary),
      labelSmall: _textStyle(12, 18, FontWeight.w500, textSecondary),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide.none,
    );
    final componentShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
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
      listTileTheme: ListTileThemeData(
        tileColor: colorScheme.surface,
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.primary,
        minTileHeight: 52,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: textSecondary,
        labelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w400,
        ),
        dividerColor: Colors.transparent,
        indicatorColor: colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colorScheme.primary
              : textSecondary;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
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
        indicatorColor: Colors.transparent,
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
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
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

import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.warningSurface,
    required this.info,
    required this.infoSurface,
    required this.heroBackground,
    required this.heroForeground,
  });

  final Color success;
  final Color warning;
  final Color warningSurface;
  final Color info;
  final Color infoSurface;
  final Color heroBackground;
  final Color heroForeground;

  static const light = AppSemanticColors(
    success: Color(0xFF059669),
    warning: Color(0xFFD97706),
    warningSurface: Color(0xFFFEF3C7),
    info: Color(0xFF0284C7),
    infoSurface: Color(0xFFE0F2FE),
    heroBackground: Color(0xFF064E3B),
    heroForeground: Color(0xFFECFDF5),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF76D3AC),
    warning: Color(0xFFFFC95C),
    warningSurface: Color(0xFF3B2E10),
    info: Color(0xFF93C9F2),
    infoSurface: Color(0xFF173247),
    heroBackground: Color(0xFF173D2E),
    heroForeground: Color(0xFFF4FAF6),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? warningSurface,
    Color? info,
    Color? infoSurface,
    Color? heroBackground,
    Color? heroForeground,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      info: info ?? this.info,
      infoSurface: infoSurface ?? this.infoSurface,
      heroBackground: heroBackground ?? this.heroBackground,
      heroForeground: heroForeground ?? this.heroForeground,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) {
      return this;
    }

    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSurface: Color.lerp(infoSurface, other.infoSurface, t)!,
      heroBackground: Color.lerp(heroBackground, other.heroBackground, t)!,
      heroForeground: Color.lerp(heroForeground, other.heroForeground, t)!,
    );
  }
}

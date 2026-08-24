import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.warningSurface,
    required this.info,
    required this.infoSurface,
  });

  final Color success;
  final Color warning;
  final Color warningSurface;
  final Color info;
  final Color infoSurface;

  static const light = AppSemanticColors(
    success: Color(0xFF2F8B69),
    warning: Color(0xFF8D6508),
    warningSurface: Color(0xFFFFF1CC),
    info: Color(0xFF236B90),
    infoSurface: Color(0xFFE4F2F8),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF76D3AC),
    warning: Color(0xFFFFC95C),
    warningSurface: Color(0xFF3B2E10),
    info: Color(0xFF93C9F2),
    infoSurface: Color(0xFF173247),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? warningSurface,
    Color? info,
    Color? infoSurface,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      info: info ?? this.info,
      infoSurface: infoSurface ?? this.infoSurface,
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
    );
  }
}

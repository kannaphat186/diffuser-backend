import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Centralized text styles used by the theme.
///
/// This gives the app one font stack everywhere instead of relying on
/// per-device system fallbacks, which was one of the reasons text looked
/// inconsistent/soft on some Android devices.
class AppTextStyles {
  AppTextStyles._();

  static TextTheme themed(TextTheme base, Color bodyColor, Color displayColor) {
    final applied = base.apply(
      fontFamily: AppTheme.fontFamily,
      bodyColor: bodyColor,
      displayColor: displayColor,
    );

    return applied.copyWith(
      bodySmall: applied.bodySmall?.copyWith(height: 1.25),
      bodyMedium: applied.bodyMedium?.copyWith(height: 1.3),
      bodyLarge: applied.bodyLarge?.copyWith(height: 1.3),
      titleMedium: applied.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: applied.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: applied.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

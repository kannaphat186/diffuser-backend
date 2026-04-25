import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  /// Register and use one embedded font family everywhere.
  /// This avoids device-specific fallback fonts that can look blurry or
  /// inconsistent, especially for Thai text at small sizes.
  static const String fontFamily = 'NotoSansThai';

  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.success : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.successBg : AppColors.cardBackground),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: Color(0x664F7EF8),
        selectionHandleColor: AppColors.primary,
      ),
      useMaterial3: true,
    );

    return base.copyWith(
      textTheme: AppTextStyles.themed(
        base.textTheme,
        AppColors.textPrimary,
        AppColors.textPrimary,
      ),
      primaryTextTheme: AppTextStyles.themed(
        base.primaryTextTheme,
        AppColors.textPrimary,
        AppColors.textPrimary,
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData(
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.bodyBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        surface: Colors.white,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.primary : Colors.grey),
        trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.primaryLight : Colors.grey.shade300),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: Color(0x664F7EF8),
        selectionHandleColor: AppColors.primary,
      ),
      useMaterial3: true,
    );

    return base.copyWith(
      textTheme: AppTextStyles.themed(
        base.textTheme,
        AppColors.textDark,
        AppColors.textDark,
      ),
      primaryTextTheme: AppTextStyles.themed(
        base.primaryTextTheme,
        AppColors.textDark,
        AppColors.textDark,
      ),
    );
  }
}

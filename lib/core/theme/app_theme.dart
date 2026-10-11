import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text.dart';

/// Light and dark themes built strictly from the design tokens.
abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        onPrimary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        surfaceContainerHighest: AppColors.background,
        outline: AppColors.hairline,
      ),
      dividerColor: AppColors.rowDivider,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: AppText.title,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: AppText.zenKaku,
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
      dividerTheme: const DividerThemeData(
        color: AppColors.rowDivider,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.tertiary,
        selectedLabelStyle: TextStyle(
          fontFamily: AppText.zenKaku,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: AppText.zenKaku,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: TextStyle(
          fontFamily: AppText.zenKaku,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.nightBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentTint,
        onPrimary: AppColors.nightBackground,
        surface: AppColors.nightPage,
        onSurface: AppColors.nightText,
        surfaceContainerHighest: AppColors.nightBackground,
        outline: Color(0xFF2A2E36),
      ),
      dividerColor: const Color(0xFF2A2E36),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.nightBackground,
        foregroundColor: AppColors.nightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: AppText.nightTitle,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: AppText.zenKaku,
        bodyColor: AppColors.nightText,
        displayColor: AppColors.nightText,
      ),
      iconTheme: const IconThemeData(color: AppColors.nightText, size: 22),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.nightPage,
        selectedItemColor: AppColors.accentTint,
        unselectedItemColor: AppColors.tertiary,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.nightPage,
        contentTextStyle: TextStyle(
          fontFamily: AppText.zenKaku,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.nightText,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

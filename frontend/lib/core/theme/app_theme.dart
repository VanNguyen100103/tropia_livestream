// =============================================================================
// app_theme.dart
// =============================================================================
// Định nghĩa ThemeData chính của ứng dụng Tropia.
//
// Cấu trúc:
//   - [AppTheme.light]: Theme sáng (main theme)
//   - [AppTheme.dark]: Theme tối (tùy chọn, dùng cho màn hình Live)
//
// Nguyên tắc thiết kế:
//   - Màu xanh lá (#2E7D32) là màu primary – thể hiện sự tươi mát của thực phẩm
//   - Màu cam (#FF6B35) là màu secondary – dùng cho giá, CTA, khuyến mãi
//   - Font mặc định: system font (Roboto on Android, SF Pro on iOS)
//   - Tất cả component đều có border radius nhất quán
//
// SỬ DỤNG:
//   MaterialApp(theme: AppTheme.light, ...)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tropia/core/constants/app_constants.dart';

abstract class AppTheme {
  // ─── Light Theme (chính) ─────────────────────────────────────────────────

  /// Theme sáng mặc định của Tropia.
  static ThemeData get light {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.secondary,
      onSecondary: AppColors.textOnSecondary,
      secondaryContainer: Color(0xFFFFE0D0),
      onSecondaryContainer: AppColors.secondaryDark,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.divider,
      surfaceContainerHighest: AppColors.surfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      // ── Scaffold & Background ──────────────────────────────────────────
      scaffoldBackgroundColor: AppColors.background,

      // ── AppBar ─────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: AppSizes.fontXl,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      // ── Bottom Navigation Bar ──────────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.navBackground,
        selectedItemColor: AppColors.navSelected,
        unselectedItemColor: AppColors.navUnselected,
        selectedLabelStyle: TextStyle(
          fontSize: AppSizes.fontXs,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: AppSizes.fontXs,
          fontWeight: FontWeight.w400,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showUnselectedLabels: true,
      ),

      // ── Card ───────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Elevated Button ────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm + 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: AppSizes.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Outlined Button ────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm + 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: AppSizes.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Text Button ────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: AppSizes.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input / TextField ──────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: AppColors.textHint,
          fontSize: AppSizes.fontMd,
        ),
      ),

      // ── Chip ───────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryContainer,
        labelStyle: const TextStyle(
          color: AppColors.primary,
          fontSize: AppSizes.fontSm,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.sm,
          vertical: AppSizes.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        ),
      ),

      // ── Divider ────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ── Text Theme ─────────────────────────────────────────────────────
      textTheme: _buildTextTheme(),

      // ── Icon Theme ─────────────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: AppSizes.iconMd,
      ),

      // ── SnackBar ───────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: AppSizes.fontMd,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        actionTextColor: AppColors.primaryLight,
      ),

      // ── Dialog ─────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: AppSizes.fontXl,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: AppSizes.fontMd,
        ),
      ),
    );
  }

  // ─── Dark Theme (dùng cho Live screen overlay) ───────────────────────────

  /// Theme tối – được dùng cho các màn hình live streaming (overlay dark).
  static ThemeData get dark {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryDark,
      onPrimaryContainer: AppColors.primaryContainer,
      secondary: AppColors.secondaryLight,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.secondaryDark,
      onSecondaryContainer: Colors.white,
      surface: Color(0xFF1E1E1E),
      onSurface: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      outline: Color(0xFF424242),
      surfaceContainerHighest: Color(0xFF2C2C2C),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF121212),
    );
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  static TextTheme _buildTextTheme() {
    return const TextTheme(
      // Display
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      // Headlines
      headlineLarge: TextStyle(
        fontSize: AppSizes.fontTitle,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: AppSizes.fontXxl,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: AppSizes.fontXl,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      // Titles
      titleLarge: TextStyle(
        fontSize: AppSizes.fontXl,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: AppSizes.fontLg,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: AppSizes.fontMd,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      // Body
      bodyLarge: TextStyle(
        fontSize: AppSizes.fontLg,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: AppSizes.fontMd,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: AppSizes.fontSm,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      // Label
      labelLarge: TextStyle(
        fontSize: AppSizes.fontMd,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: AppSizes.fontSm,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: AppSizes.fontXs,
        fontWeight: FontWeight.w400,
        color: AppColors.textHint,
      ),
    );
  }
}

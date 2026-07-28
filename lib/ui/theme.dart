import 'package:flutter/material.dart';

/// Uygulamanin ortak renk paleti ve stil yardimcilari.
class AppColors {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF11111B);
  static const card = Color(0xFF1E1E2E);
  static const cardDeep = Color(0xFF0D0D14);
  static const primary = Color(0xFF6C5CE7);
  static const primaryLight = Color(0xFF8B7CF6);
  static const accent = Color(0xFF00D2D3);
  static const textPrimary = Color(0xFFECEBF7);
  static const textSecondary = Color(0xFF9E9CB8);
  static const textFaint = Color(0xFF6E6C8A);
  static const success = Color(0xFF2ECC71);
  static const danger = Color(0xFFE74C3C);

  /// Mor -> acik mor gecis (butonlar, kullanici balonu, baslik).
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C5CE7), Color(0xFF8B7CF6)],
  );
}

/// Uygulamanin koyu temasi.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.surface,
      primary: AppColors.primary,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerColor: const Color(0xFF2A2A3A),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.card,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: Color(0xFF3A3A50)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
  );
}

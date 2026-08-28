import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Shared high-contrast theme for the driver experience.
class AppTheme {
  AppTheme._();

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primaryHover,
      secondary: AppColors.info,
      onSecondary: AppColors.white,
      error: AppColors.error,
      onError: AppColors.white,
      surface: AppColors.white,
      onSurface: AppColors.neutral900,
      surfaceContainerHighest: AppColors.neutral100,
      onSurfaceVariant: AppColors.neutral600,
      outline: AppColors.neutral200,
    ),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: GoogleFonts.interTextTheme().copyWith(
      headlineLarge:
          GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineMedium:
          GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall:
          GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge:
          GoogleFonts.inter(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w700),
    ),

    // ── AppBar ──────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
    ),

    // ── Cards ───────────────────────────────────────────
    cardTheme: CardTheme(
      color: AppColors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),

    // ── InputDecoration ─────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.neutral100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.neutral900, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      labelStyle: const TextStyle(
        color: AppColors.textTertiary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(
        color: AppColors.textHint,
        fontSize: 14,
      ),
    ),

    // ── Elevated Button ─────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.neutral900,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        minimumSize: const Size(double.infinity, 48),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // ── Outlined Button ─────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        minimumSize: const Size(double.infinity, 48),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // ── Bottom Navigation ───────────────────────────────
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.navSelected,
      unselectedItemColor: AppColors.navUnselected,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
      unselectedLabelStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
      showUnselectedLabels: true,
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.neutral900
                : AppColors.neutral400,
            size: 22,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.neutral900
                : AppColors.neutral500,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          )),
    ),

    // ── Divider ─────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.primaryHover,
      onPrimaryContainer: AppColors.primaryLight,
      secondary: AppColors.info,
      onSecondary: AppColors.white,
      tertiary: AppColors.warning,
      onTertiary: AppColors.black,
      error: AppColors.error,
      onError: AppColors.white,
      surface: AppColors.neutral900,
      onSurface: AppColors.neutral50,
      surfaceContainerHighest: AppColors.neutral800,
      onSurfaceVariant: AppColors.neutral300,
      outline: AppColors.neutral600,
      outlineVariant: AppColors.neutral700,
    ),
    scaffoldBackgroundColor: AppColors.darkBackground,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  );
}

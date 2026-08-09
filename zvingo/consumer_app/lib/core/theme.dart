import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static final ColorScheme _colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: AppColors.textOnPrimary,
    primaryContainer: AppColors.primarySurface,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: AppColors.accent,
    onSecondary: AppColors.textPrimary,
    secondaryContainer: AppColors.accentSurface,
    onSecondaryContainer: AppColors.textPrimary,
    error: AppColors.error,
    errorContainer: AppColors.errorSurface,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    outline: AppColors.border,
    outlineVariant: AppColors.divider,
    shadow: AppColors.textPrimary,
  );

  static final TextTheme _textTheme = ThemeData.light().textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
    textTheme: _textTheme,
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: _textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardTheme(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.divider),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      labelStyle: _textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: _textTheme.bodyMedium?.copyWith(color: AppColors.textHint),
      errorStyle: _textTheme.bodySmall?.copyWith(color: AppColors.error),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textTertiary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        minimumSize: const Size(48, 52),
        textStyle: _textTheme.labelLarge?.copyWith(
          color: AppColors.textOnPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        minimumSize: const Size(48, 52),
        textStyle: _textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: _textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(44, 44),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primarySurface,
      shadowColor: AppColors.textPrimary.withOpacity(0.08),
      elevation: 8,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.navUnselected,
          size: 23,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => _textTheme.labelSmall?.copyWith(
          color: states.contains(WidgetState.selected)
              ? AppColors.primaryDark
              : AppColors.navUnselected,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: _textTheme.bodyMedium?.copyWith(color: AppColors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceMuted,
      selectedColor: AppColors.primarySurface,
      labelStyle: _textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      secondaryLabelStyle: _textTheme.labelMedium?.copyWith(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w700,
      ),
      shape: const StadiumBorder(),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.primaryLight,
      circularTrackColor: AppColors.primaryLight,
    ),
  );
}

import 'package:flutter/material.dart';

/// Zvingo's accessible brand and semantic color tokens.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF087A55);
  static const Color primaryDark = Color(0xFF05573D);
  static const Color primaryLight = Color(0xFFD8F5E9);
  static const Color primarySurface = Color(0xFFECFDF5);
  static const Color accent = Color(0xFFFFB547);
  static const Color accentSurface = Color(0xFFFFF5DF);

  // Neutrals
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF7F8F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F3F1);
  static const Color card = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE8ECE9);
  static const Color border = Color(0xFFD6DDD8);
  static const Color shimmerBase = Color(0xFFE5EAE7);
  static const Color shimmerHighlight = Color(0xFFF7F9F8);

  // Text
  static const Color textPrimary = Color(0xFF17211B);
  static const Color textSecondary = Color(0xFF536159);
  static const Color textTertiary = Color(0xFF6B786F);
  static const Color textHint = Color(0xFF89968E);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Semantic
  static const Color rating = Color(0xFFF4A100);
  static const Color warning = Color(0xFFB96800);
  static const Color warningSurface = Color(0xFFFFF4DE);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorSurface = Color(0xFFFFEDEA);
  static const Color success = Color(0xFF087A55);
  static const Color info = Color(0xFF246BCE);

  // Promotional accents
  static const Color dealTag = Color(0xFFC9362B);
  static const Color dealTagBg = Color(0xFFFFEFED);
  static const Color selectedDark = Color(0xFF17211B);
  static const Color warmSurface = Color(0xFFFFF8EE);

  // Navigation
  static const Color navSelected = primary;
  static const Color navUnselected = textTertiary;
}

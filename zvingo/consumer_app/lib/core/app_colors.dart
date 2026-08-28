import 'package:flutter/material.dart';

/// Zvingo's accessible brand and semantic color tokens.
class AppColors {
  AppColors._();

  // Brand
  // Transactional actions intentionally use near-black, matching the partner
  // dashboard and the confident, low-chrome interaction language of modern
  // mobility apps. Green remains semantic rather than being used everywhere.
  static const Color primary = Color(0xFF111311);
  static const Color primaryDark = Color(0xFF050605);
  static const Color primaryLight = Color(0xFFE5E6E2);
  static const Color primarySurface = Color(0xFFF0F1ED);
  static const Color accent = Color(0xFFD7F654);
  static const Color accentSurface = Color(0xFFF4FBCF);
  static const Color brandGreen = Color(0xFF0A8F5B);
  static const Color brandGreenDark = Color(0xFF06643F);
  static const Color brandGreenSurface = Color(0xFFE9F8F1);

  // Neutrals
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF6F6F4);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEFEFEC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE7E7E3);
  static const Color border = Color(0xFFDCDDD8);
  static const Color shimmerBase = Color(0xFFE5EAE7);
  static const Color shimmerHighlight = Color(0xFFF7F9F8);

  // Text
  static const Color textPrimary = Color(0xFF101211);
  static const Color textSecondary = Color(0xFF545754);
  static const Color textTertiary = Color(0xFF737672);
  static const Color textHint = Color(0xFF8E918D);
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
  static const Color selectedDark = Color(0xFF101211);
  static const Color warmSurface = Color(0xFFFFF8EE);

  // Navigation
  static const Color navSelected = selectedDark;
  static const Color navUnselected = textTertiary;
}

import 'package:flutter/material.dart';

/// Color system mirroring the Kotlin driver app's Color.kt
class AppColors {
  AppColors._();

  // ── Primary Brand Colors ──────────────────────────────
  static const Color primary = Color(0xFF10B981);
  static const Color primaryHover = Color(0xFF059669);
  static const Color primaryLight = Color(0xFFD1FAE5);
  static const Color primarySurface = Color(0xFFECFDF5);

  // ── Neutrals ──────────────────────────────────────────
  static const Color neutral50 = Color(0xFFF8FAFC);
  static const Color neutral100 = Color(0xFFF1F5F9);
  static const Color neutral200 = Color(0xFFE2E8F0);
  static const Color neutral300 = Color(0xFFCBD5E1);
  static const Color neutral400 = Color(0xFF94A3B8);
  static const Color neutral500 = Color(0xFF64748B);
  static const Color neutral600 = Color(0xFF475569);
  static const Color neutral700 = Color(0xFF334155);
  static const Color neutral800 = Color(0xFF1E293B);
  static const Color neutral900 = Color(0xFF0F172A);

  // ── Semantic Colors ───────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ── Common Aliases ────────────────────────────────────
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color background = neutral50;
  static const Color surface = Colors.white;
  static const Color divider = neutral200;
  static const Color border = neutral200;

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary = neutral900;
  static const Color textSecondary = neutral600;
  static const Color textTertiary = neutral400;
  static const Color textHint = neutral400;
  static const Color textOnPrimary = Colors.white;

  // ── Navigation ────────────────────────────────────────
  static const Color navSelected = primary;
  static const Color navUnselected = neutral400;

  // ── Dark theme ────────────────────────────────────────
  static const Color darkBackground = neutral900;
  static const Color darkSurface = neutral900;
  static const Color darkSurfaceVariant = neutral800;
  static const Color darkTextPrimary = neutral50;
  static const Color darkTextSecondary = neutral300;
}

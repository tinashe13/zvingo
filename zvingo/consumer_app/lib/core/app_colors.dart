import 'package:flutter/material.dart';

/// Zvingo brand colors — Green-based palette inspired by DoorDash layout
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────
  static const Color primary       = Color(0xFF10B981);
  static const Color primaryDark   = Color(0xFF059669);
  static const Color primaryLight  = Color(0xFFD1FAE5);
  static const Color primarySurface = Color(0xFFD1FAE5); // Used for active backgrounds

  // ── Neutrals ───────────────────────────────────────────
  static const Color white         = Color(0xFFFFFFFF);
  static const Color background    = Color(0xFFF8FAFC); // neutral-50
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color card          = Color(0xFFFFFFFF);
  static const Color divider       = Color(0xFFF1F5F9); // neutral-100
  static const Color border        = Color(0xFFE2E8F0); // neutral-200
  static const Color shimmerBase   = Color(0xFFE2E8F0);
  static const Color shimmerHighlight = Color(0xFFF8FAFC);

  // ── Text ───────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF0F172A); // neutral-900
  static const Color textSecondary = Color(0xFF475569); // neutral-600
  static const Color textTertiary  = Color(0xFF64748B); // neutral-500
  static const Color textHint      = Color(0xFF94A3B8); // neutral-400
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Semantic ───────────────────────────────────────────
  static const Color rating        = Color(0xFFFFB800); // warning
  static const Color warning       = Color(0xFFF59E0B);
  static const Color error         = Color(0xFFEF4444);
  static const Color success       = Color(0xFF22C55E);
  static const Color info          = Color(0xFF3B82F6);

  // ── DoorDash-style accents ────────────────────────────
  static const Color dealTag       = Color(0xFFE53935); // deal/promo tag icons
  static const Color dealTagBg     = Color(0xFFFFF0F0); // deal card background
  static const Color selectedDark  = Color(0xFF191919); // selected tabs/tips dark bg
  static const Color warmSurface   = Color(0xFFF5F0EB); // warm-toned surface bg

  // ── Bottom Nav ─────────────────────────────────────────
  static const Color navSelected   = Color(0xFF10B981);
  static const Color navUnselected = Color(0xFF94A3B8);
}

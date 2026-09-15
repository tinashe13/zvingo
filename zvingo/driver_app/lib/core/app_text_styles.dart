import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Zvingo typography tokens — driver surface.
///
/// Normative source: `docs/DESIGN_SYSTEM.md` §2. Identifier names match
/// `consumer_app/lib/core/app_text_styles.dart` (§6).
///
/// **Family.** The family is intentionally left unset on these constants so
/// they inherit the ambient font. `AppTheme` applies Inter (via `google_fonts`)
/// to the whole `TextTheme`, with the platform default as the fallback — which
/// is exactly what §2 asks for ("bundled Inter, fallback Roboto"). Keeping the
/// family off the constants is what lets every one of them stay `const`.
///
/// **Tabular figures.** Every style that can render money, time, distance or a
/// countdown carries [FontFeature.tabularFigures]. Driver earnings and ETAs
/// update live; proportional digits make the number jitter as it counts, which
/// reads as a glitch at a glance.
///
/// **Driver ergonomics.** This app is read one-handed, outdoors, often at
/// speed. Anything a driver must act on is ≥15pt and ≥600 weight. [caption]
/// and [overline] are for *non-critical* metadata only — never put a street
/// name, a payout or a countdown in them.
class AppTextStyles {
  AppTextStyles._();

  /// Applied to any style that renders digits which change over time.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // ───────────────────────────────────────────────────────────────────────
  // §2 Core roles
  // ───────────────────────────────────────────────────────────────────────

  /// 32/38 · 800 · −0.6 — hero numbers (earnings total, order total).
  /// Tabular: this is almost always a number.
  static const TextStyle display = TextStyle(
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
    fontFeatures: tabular,
  );

  /// 26/32 · 800 · −0.5 — screen titles.
  static const TextStyle h1 = TextStyle(
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  /// 21/27 · 700 · −0.4 — section headers, merchant name.
  static const TextStyle h2 = TextStyle(
    fontSize: 21,
    height: 27 / 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  /// 17/23 · 700 · −0.2 — card titles.
  static const TextStyle h3 = TextStyle(
    fontSize: 17,
    height: 23 / 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  /// 15/22 · 400 — default body copy.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  /// 15/22 · 600 — emphasis within body.
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// 13/18 · 500 — metadata, helper text. Non-critical information only.
  /// Carries tabular figures because it frequently renders ETA and distance.
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    fontFeatures: tabular,
  );

  /// 11/14 · 700 · +0.8 · UPPERCASE — section eyebrows, status chips.
  /// Callers are responsible for upper-casing the string.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );

  /// 15/20 · 700 · −0.1 — all button labels.
  ///
  /// Colour is deliberately unset: button widgets supply the foreground so one
  /// token serves filled, outlined and destructive variants.
  static const TextStyle button = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  // ───────────────────────────────────────────────────────────────────────
  // Driver-specific numeric roles
  //
  // The offer card and the earnings screen are read in about one second at
  // arm's length. These sit above `display` on purpose.
  // ───────────────────────────────────────────────────────────────────────

  /// 48/52 · 900 — the payout on an offer card and the day's earnings total.
  /// The single largest thing on its screen, by design.
  static const TextStyle moneyHero = TextStyle(
    fontSize: 48,
    height: 52 / 48,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.6,
    color: AppColors.textPrimary,
    fontFeatures: tabular,
  );

  /// 24/28 · 800 — secondary money (tips, per-trip payout, weekly subtotal).
  static const TextStyle moneyLarge = TextStyle(
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
    fontFeatures: tabular,
  );

  /// 17/22 · 700 — inline money inside a row or list tile.
  static const TextStyle money = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
    fontFeatures: tabular,
  );

  /// 20/24 · 800 — distance, ETA and countdown values on glanceable rows.
  /// Above the 15pt floor because these are act-on-it numbers.
  static const TextStyle metric = TextStyle(
    fontSize: 20,
    height: 24 / 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
    fontFeatures: tabular,
  );

  /// 15/20 · 700 — the label inside a slide-to-confirm track. Reads as an
  /// instruction, so it is button-weight rather than body-weight.
  static const TextStyle slideLabel = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  // ───────────────────────────────────────────────────────────────────────
  // Material-named aliases
  //
  // These keep `Theme.of(context).textTheme.*` and older call sites aligned
  // with the token scale instead of drifting back to Material defaults.
  // ───────────────────────────────────────────────────────────────────────

  static const TextStyle displayLarge = display;
  static const TextStyle displayMedium = h1;
  static const TextStyle displaySmall = h2;

  static const TextStyle headlineLarge = h1;
  static const TextStyle headlineMedium = h2;
  static const TextStyle headlineSmall = h3;

  static const TextStyle titleLarge = h2;
  static const TextStyle titleMedium = h3;
  static const TextStyle titleSmall = bodyStrong;

  static const TextStyle bodyLarge = body;
  static const TextStyle bodyMedium = body;
  static const TextStyle bodySmall = caption;

  static const TextStyle labelLarge = button;
  static const TextStyle labelMedium = caption;
  static const TextStyle labelSmall = overline;

  /// Money in a list row. Alias of [money], kept for consumer-app parity.
  static const TextStyle price = money;

  /// Prominent money. Alias of [moneyLarge], kept for consumer-app parity.
  static const TextStyle priceLarge = moneyLarge;

  /// Struck-through "was" price.
  static const TextStyle priceStrikethrough = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
    decoration: TextDecoration.lineThrough,
    fontFeatures: tabular,
  );

  /// Driver approval / acceptance rating percentage.
  static const TextStyle approvalRating = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    fontFeatures: tabular,
  );

  // ───────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────

  /// Returns [style] with the colour that is legible on the current theme.
  ///
  /// Use this when a token is applied directly (rather than through
  /// `Theme.of(context).textTheme`) inside a widget that must support dark
  /// mode — the constants above hard-code the light-theme text colours.
  static TextStyle onSurface(BuildContext context, TextStyle style) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return style;
    final light = style.color;
    final dark = switch (light) {
      AppColors.textSecondary => AppColors.darkTextSecondary,
      AppColors.textTertiary => AppColors.darkTextTertiary,
      _ => AppColors.darkTextPrimary,
    };
    return style.copyWith(color: dark);
  }
}

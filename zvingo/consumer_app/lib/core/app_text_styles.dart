import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Zvingo typography tokens — the Flutter binding of §2 of
/// `docs/DESIGN_SYSTEM.md`.
///
/// | Role          | Size / Line height | Weight | Tracking |
/// |---------------|--------------------|--------|----------|
/// | [display]     | 32 / 38            | 800    | −0.6     |
/// | [h1]          | 26 / 32            | 800    | −0.5     |
/// | [h2]          | 21 / 27            | 700    | −0.4     |
/// | [h3]          | 17 / 23            | 700    | −0.2     |
/// | [body]        | 15 / 22            | 400    | 0        |
/// | [bodyStrong]  | 15 / 22            | 600    | 0        |
/// | [caption]     | 13 / 18            | 500    | 0        |
/// | [overline]    | 11 / 14            | 700    | +0.8 UC  |
/// | [button]      | 15 / 20            | 700    | −0.1     |
///
/// Anything that renders **money or time** must use one of the [money] /
/// [time] styles (or call [tabular] on its own style) so digits do not jitter
/// as values update.
///
/// Rules: never more than 3 sizes in one card; never centre-align a paragraph
/// longer than two lines; always truncate with a fixed `maxLines`.
class AppTextStyles {
  AppTextStyles._();

  /// The bundled family. The design system specifies Inter with a Roboto
  /// fallback; only Roboto ships in `assets/fonts/` today, so Roboto is the
  /// resolved family on every platform.
  static const String fontFamily = 'Roboto';

  /// Tabular (monospaced) figures — required for money, ETAs and counters.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // ───────────────────────────────────────────────────────────────────────
  // §2 Canonical roles
  // ───────────────────────────────────────────────────────────────────────

  /// Hero numbers: order total, earnings total.
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
  );

  /// Screen titles.
  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  /// Section headers, restaurant name.
  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 21,
    height: 27 / 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  /// Card titles, menu item name.
  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 23 / 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  /// Default body copy.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  /// Emphasis within body copy.
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  /// Metadata, ETA, distance, helper text.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: AppColors.textSecondary,
  );

  /// Section eyebrows and status chips. Always render the text UPPERCASE.
  static const TextStyle overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );

  /// All button labels.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    color: AppColors.textOnDark,
  );

  // ───────────────────────────────────────────────────────────────────────
  // Money & time — tabular figures are mandatory here.
  // ───────────────────────────────────────────────────────────────────────

  /// Inline money, e.g. a menu item price. 15/22, 700, tabular.
  static const TextStyle money = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  /// Prominent money, e.g. a cart subtotal. 21/27, 800, tabular.
  static const TextStyle moneyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 21,
    height: 27 / 21,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  /// Hero money, e.g. the order total on checkout. 32/38, 800, tabular.
  static const TextStyle moneyDisplay = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  /// A struck-through "was" price. Tabular so it aligns under [money].
  static const TextStyle moneyStrikethrough = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
    decoration: TextDecoration.lineThrough,
    fontFeatures: tabularFigures,
  );

  /// ETAs, countdowns, distances. 13/18, 600, tabular.
  static const TextStyle time = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textSecondary,
    fontFeatures: tabularFigures,
  );

  /// A large live ETA, e.g. on the order-tracking header. 21/27, 800, tabular.
  static const TextStyle timeLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 21,
    height: 27 / 21,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  /// Returns [style] with tabular figures applied. Use for any numeric value
  /// that updates in place.
  static TextStyle tabular(TextStyle style) =>
      style.copyWith(fontFeatures: tabularFigures);

  // ───────────────────────────────────────────────────────────────────────
  // Compatibility aliases.
  //
  // Material-flavoured names that predate the token layer and are still
  // referenced in the feature folders. They resolve to the canonical roles
  // above. Prefer the canonical names in new code.
  // ───────────────────────────────────────────────────────────────────────

  /// Alias of [h1].
  static const TextStyle headlineLarge = h1;

  /// Alias of [h2].
  static const TextStyle headlineMedium = h2;

  /// Alias of [h2].
  static const TextStyle titleLarge = h2;

  /// Alias of [h3].
  static const TextStyle titleMedium = h3;

  /// Alias of [h3].
  static const TextStyle titleSmall = h3;

  /// Alias of [body].
  static const TextStyle bodyLarge = body;

  /// Alias of [body].
  static const TextStyle bodyMedium = body;

  /// Alias of [caption].
  static const TextStyle bodySmall = caption;

  /// Alias of [button], coloured for light surfaces.
  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    color: AppColors.textPrimary,
  );

  /// Alias of [overline].
  static const TextStyle labelSmall = overline;

  /// Alias of [money].
  static const TextStyle price = money;

  /// Alias of [moneyLarge].
  static const TextStyle priceLarge = moneyLarge;

  /// Alias of [moneyStrikethrough].
  static const TextStyle priceStrikethrough = moneyStrikethrough;

  /// Small approval-rating percentage next to a star.
  static const TextStyle approvalRating = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    fontFeatures: tabularFigures,
  );
}

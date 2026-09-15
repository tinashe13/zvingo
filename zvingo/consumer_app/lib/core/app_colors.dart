import 'package:flutter/material.dart';

/// Zvingo colour tokens — the Flutter binding of §1 of `docs/DESIGN_SYSTEM.md`.
///
/// **Never** write a raw `Color(0x...)` in a widget. Always reference a token
/// from this class so the three surfaces (consumer, driver, merchant) stay in
/// lockstep. Token names are identical to the driver app and to the merchant
/// dashboard's CSS custom properties.
///
/// ```dart
/// Container(color: AppColors.surface)
/// Text('Delivered', style: TextStyle(color: AppColors.success))
/// ```
class AppColors {
  AppColors._();

  // ───────────────────────────────────────────────────────────────────────
  // §1.3 Neutrals — shared 10-step ramp, identical across all three surfaces.
  // ───────────────────────────────────────────────────────────────────────

  /// `neutral/0` — pure white. Card and sheet surfaces.
  static const Color neutral0 = Color(0xFFFFFFFF);

  /// `neutral/50` — app background.
  static const Color neutral50 = Color(0xFFF7F7F5);

  /// `neutral/100` — muted surface / input fill.
  static const Color neutral100 = Color(0xFFEFEFEC);

  /// `neutral/200` — hairline borders and dividers.
  static const Color neutral200 = Color(0xFFE2E2DE);

  /// `neutral/300` — heavier borders, disabled outlines.
  static const Color neutral300 = Color(0xFFCDCDC7);

  /// `neutral/400` — tertiary text, unselected nav icons.
  static const Color neutral400 = Color(0xFF999B96);

  /// `neutral/500` — low-emphasis text on light surfaces.
  static const Color neutral500 = Color(0xFF737570);

  /// `neutral/600` — secondary text.
  static const Color neutral600 = Color(0xFF555752);

  /// `neutral/700` — strong secondary text / dark icons.
  static const Color neutral700 = Color(0xFF383A37);

  /// `neutral/800` — near-black surfaces (snackbars, tooltips).
  static const Color neutral800 = Color(0xFF222421);

  /// `neutral/900` — primary text and the action colour.
  static const Color neutral900 = Color(0xFF101210);

  // ───────────────────────────────────────────────────────────────────────
  // §1.1 Brand
  // ───────────────────────────────────────────────────────────────────────

  /// `brand/green` — identity, success, "online", money-positive.
  static const Color brandGreen = Color(0xFF0A8F5B);

  /// `brand/green-dark` — hover / pressed on brand green.
  static const Color brandGreenDark = Color(0xFF076C45);

  /// `brand/green-surface` — tinted background behind brand content.
  static const Color brandGreenSurface = Color(0xFFE9F8F1);

  /// `brand/lime` — **accent only**: highlights, badges, "new", progress fill.
  /// Never use as a full-width button fill.
  static const Color brandLime = Color(0xFFD7F654);

  /// `brand/lime-surface` — tinted background behind lime accents.
  static const Color brandLimeSurface = Color(0xFFF4FBCF);

  /// Alias of [brandLime]. Kept because widgets across the app say `accent`.
  static const Color accent = brandLime;

  /// Alias of [brandLimeSurface].
  static const Color accentSurface = brandLimeSurface;

  // ───────────────────────────────────────────────────────────────────────
  // §1.2 Action — the primary interactive colour is near-black, not green.
  // ───────────────────────────────────────────────────────────────────────

  /// `action/default` — filled primary buttons, selected states, active nav.
  static const Color actionDefault = neutral900;

  /// `action/hover`.
  static const Color actionHover = Color(0xFF2A2C29);

  /// `action/pressed`.
  static const Color actionPressed = Color(0xFF050605);

  /// `action/disabled-bg` — disabled fill.
  static const Color actionDisabledBg = neutral200;

  /// `action/disabled-fg` — disabled label.
  static const Color actionDisabledFg = neutral400;

  // ───────────────────────────────────────────────────────────────────────
  // §1.3 Roles
  // ───────────────────────────────────────────────────────────────────────

  /// Scaffold background (`neutral/50`).
  static const Color background = neutral50;

  /// Card / sheet surface (`neutral/0`).
  static const Color surface = neutral0;

  /// Muted surface: input fill, chip rest state (`neutral/100`).
  static const Color surfaceMuted = neutral100;

  /// Hairline border (`neutral/200`).
  static const Color border = neutral200;

  /// Divider (`neutral/200`).
  static const Color divider = neutral200;

  /// Primary text (`neutral/900`).
  static const Color textPrimary = neutral900;

  /// Secondary text (`neutral/600`).
  static const Color textSecondary = neutral600;

  /// Tertiary text (`neutral/400`). Legal **only** on `neutral/0` /
  /// `neutral/50` and only for non-essential metadata.
  static const Color textTertiary = neutral400;

  /// Text on dark fills (`neutral/0`).
  static const Color textOnDark = neutral0;

  // ───────────────────────────────────────────────────────────────────────
  // §1.4 Semantic — never signal state with colour alone; pair with an icon.
  // ───────────────────────────────────────────────────────────────────────

  /// Delivered, paid, online, confirmed.
  static const Color success = brandGreen;

  /// Tint behind [success].
  static const Color successSurface = brandGreenSurface;

  /// Waiting, delayed, action needed soon.
  static const Color warning = Color(0xFFB96800);

  /// Tint behind [warning].
  static const Color warningSurface = Color(0xFFFFF4DE);

  /// Failed, cancelled, destructive.
  static const Color error = Color(0xFFBA1A1A);

  /// Tint behind [error].
  static const Color errorSurface = Color(0xFFFFEDEA);

  /// Neutral informational.
  static const Color info = Color(0xFF246BCE);

  /// Tint behind [info].
  static const Color infoSurface = Color(0xFFEAF1FC);

  /// Star fills only.
  static const Color rating = Color(0xFFF4A100);

  /// Discounts, promo tags, price drops.
  static const Color deal = Color(0xFFC9362B);

  /// Tint behind [deal].
  static const Color dealSurface = Color(0xFFFFEFED);

  // ───────────────────────────────────────────────────────────────────────
  // Shimmer (skeleton loading — §4.3)
  // ───────────────────────────────────────────────────────────────────────

  /// Base colour of a shimmer skeleton block.
  static const Color shimmerBase = neutral200;

  /// Travelling highlight of a shimmer skeleton block.
  static const Color shimmerHighlight = neutral50;

  // ───────────────────────────────────────────────────────────────────────
  // Compatibility aliases.
  //
  // These names predate the token layer and are still referenced across the
  // feature folders. They now point at the canonical ramp above so there is
  // exactly one source of truth. Prefer the canonical names in new code.
  // ───────────────────────────────────────────────────────────────────────

  /// Deprecated alias for [actionDefault].
  static const Color primary = actionDefault;

  /// Deprecated alias for [actionPressed].
  static const Color primaryDark = actionPressed;

  /// Deprecated alias for [neutral200].
  static const Color primaryLight = neutral200;

  /// Deprecated alias for [neutral100].
  static const Color primarySurface = neutral100;

  /// Deprecated alias for [actionDefault]. Use [actionDefault].
  static const Color selectedDark = actionDefault;

  /// Deprecated alias for [neutral0].
  static const Color white = neutral0;

  /// Deprecated alias for [surface].
  static const Color card = surface;

  /// Deprecated alias for [textTertiary].
  static const Color textHint = textTertiary;

  /// Deprecated alias for [textOnDark].
  static const Color textOnPrimary = textOnDark;

  /// Deprecated alias for [deal].
  static const Color dealTag = deal;

  /// Deprecated alias for [dealSurface].
  static const Color dealTagBg = dealSurface;

  /// Deprecated alias for [warningSurface].
  static const Color warmSurface = warningSurface;

  // ───────────────────────────────────────────────────────────────────────
  // Navigation (§5.4)
  // ───────────────────────────────────────────────────────────────────────

  /// Selected bottom-tab icon + label.
  static const Color navSelected = actionDefault;

  /// Unselected bottom-tab icon + label.
  static const Color navUnselected = neutral400;
}

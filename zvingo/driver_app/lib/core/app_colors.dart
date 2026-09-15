import 'package:flutter/material.dart';

/// Zvingo colour tokens — driver surface.
///
/// Normative source: `docs/DESIGN_SYSTEM.md` §1.
///
/// **Identifier parity is a hard requirement (§6):** every name exposed here
/// also exists in `consumer_app/lib/core/app_colors.dart` with the same
/// meaning, so a developer moving between the two Flutter apps never has to
/// relearn token names.
///
/// Rules that apply to every consumer of this file:
/// * Never write a raw hex value in a widget — reference a token.
/// * Never signal state with colour alone; pair it with an icon and/or label.
/// * At most three accent colours visible in one viewport.
///
/// Driver-specific note: this app is used outdoors in direct sunlight, so
/// figure/ground separation is deliberately stronger than on the consumer
/// surface. Prefer [neutral900] on [neutral0] over mid-grey on grey.
class AppColors {
  AppColors._();

  // ───────────────────────────────────────────────────────────────────────
  // §1.1 Brand
  // ───────────────────────────────────────────────────────────────────────

  /// Identity green. Logo, brand moments, success, driver "online",
  /// money-positive. Never a generic button fill — see [action].
  static const Color brandGreen = Color(0xFF0A8F5B);

  /// Hover / pressed state on [brandGreen].
  static const Color brandGreenDark = Color(0xFF076C45);

  /// Tinted background behind brand-green content.
  static const Color brandGreenSurface = Color(0xFFE9F8F1);

  /// Accent lime. Highlights, badges, "new", progress fill.
  /// **Never** a full-width button fill.
  static const Color accent = Color(0xFFD7F654);

  /// Tinted background behind lime accents.
  static const Color accentSurface = Color(0xFFF4FBCF);

  /// Long-form alias for [accent] used by the dashboard token map.
  static const Color brandLime = accent;

  /// Long-form alias for [accentSurface].
  static const Color brandLimeSurface = accentSurface;

  // ───────────────────────────────────────────────────────────────────────
  // §1.2 Action — the primary interactive colour
  //
  // Transactional actions use near-black, not green. This keeps green
  // meaningful as a *semantic* signal (online, paid, delivered) instead of
  // spending it on every button.
  // ───────────────────────────────────────────────────────────────────────

  /// Filled primary buttons, selected states, active nav. `action/default`.
  static const Color action = Color(0xFF101210);

  /// `action/hover`.
  static const Color actionHover = Color(0xFF2A2C29);

  /// `action/pressed`.
  static const Color actionPressed = Color(0xFF050605);

  /// `action/disabled-bg`.
  static const Color actionDisabledBg = Color(0xFFE2E2DE);

  /// `action/disabled-fg` — the label on a disabled action.
  static const Color actionDisabledFg = Color(0xFF999B96);

  /// Primary interactive colour. Alias of [action]; kept because the majority
  /// of existing widget code reads `AppColors.primary`.
  static const Color primary = action;

  /// Pressed/hover companion to [primary]. Alias of [actionHover].
  static const Color primaryHover = actionHover;

  /// Darkest step of the action ramp. Alias of [actionPressed].
  static const Color primaryDark = actionPressed;

  /// Low-emphasis tint of [primary] — icon chips, selected pills.
  static const Color primaryLight = Color(0xFFE2E2DE);

  /// Very low-emphasis tint of [primary] — section backgrounds.
  static const Color primarySurface = Color(0xFFEFEFEC);

  /// The near-black used for "selected" affordances. Alias of [action].
  static const Color selectedDark = action;

  // ───────────────────────────────────────────────────────────────────────
  // §1.3 Neutrals — shared 10-step ramp, identical across all three surfaces
  // ───────────────────────────────────────────────────────────────────────

  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFF7F7F5);
  static const Color neutral100 = Color(0xFFEFEFEC);
  static const Color neutral200 = Color(0xFFE2E2DE);
  static const Color neutral300 = Color(0xFFCDCDC7);
  static const Color neutral400 = Color(0xFF999B96);
  static const Color neutral500 = Color(0xFF737570);
  static const Color neutral600 = Color(0xFF555752);
  static const Color neutral700 = Color(0xFF383A37);
  static const Color neutral800 = Color(0xFF222421);
  static const Color neutral900 = Color(0xFF101210);

  // ── Neutral roles (§1.3) ───────────────────────────────────────────────

  static const Color white = neutral0;
  static const Color black = neutral900;

  /// Screen background.
  static const Color background = neutral50;

  /// Card / sheet / app-bar surface.
  static const Color surface = neutral0;

  /// Recessed surface: input fills, inert chips, skeleton bases.
  static const Color surfaceMuted = neutral100;

  /// Alias of [surface], for call sites that read `AppColors.card`.
  static const Color card = surface;

  static const Color divider = neutral200;
  static const Color border = neutral200;

  // ── Text roles ─────────────────────────────────────────────────────────

  static const Color textPrimary = neutral900;
  static const Color textSecondary = neutral600;

  /// Only legal on [neutral0] / [neutral50], and only for non-essential
  /// metadata (§1.5).
  static const Color textTertiary = neutral400;

  /// Placeholder / hint text inside inputs.
  static const Color textHint = neutral400;

  /// Text drawn on top of [action], [brandGreen], [error] and other dark fills.
  static const Color textOnDark = neutral0;

  /// Alias of [textOnDark].
  static const Color textOnPrimary = neutral0;

  // ── Shimmer / skeleton ─────────────────────────────────────────────────

  static const Color shimmerBase = neutral200;
  static const Color shimmerHighlight = neutral100;

  // ───────────────────────────────────────────────────────────────────────
  // §1.4 Semantic
  // ───────────────────────────────────────────────────────────────────────

  /// Delivered, paid, online, confirmed.
  static const Color success = Color(0xFF0A8F5B);
  static const Color successSurface = Color(0xFFE9F8F1);

  /// Waiting, delayed, action needed soon.
  static const Color warning = Color(0xFFB96800);
  static const Color warningSurface = Color(0xFFFFF4DE);

  /// Failed, cancelled, destructive.
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorSurface = Color(0xFFFFEDEA);

  /// Neutral informational.
  static const Color info = Color(0xFF246BCE);
  static const Color infoSurface = Color(0xFFEAF1FC);

  /// Star fills only.
  static const Color rating = Color(0xFFF4A100);

  /// Discounts, promo tags, price drops.
  static const Color deal = Color(0xFFC9362B);
  static const Color dealSurface = Color(0xFFFFEFED);

  /// Aliases kept for consumer-app parity.
  static const Color dealTag = deal;
  static const Color dealTagBg = dealSurface;

  /// Warm neutral used behind promotional/earnings content.
  static const Color warmSurface = Color(0xFFFFF8EE);

  // ───────────────────────────────────────────────────────────────────────
  // Navigation
  // ───────────────────────────────────────────────────────────────────────

  static const Color navSelected = action;
  static const Color navUnselected = neutral400;

  // ───────────────────────────────────────────────────────────────────────
  // Dark theme — drivers work nights.
  //
  // The ramp is inverted rather than re-invented: surfaces climb from
  // neutral900 upward so elevation still reads as "lighter", and text uses
  // the pale end of the same ramp. Semantic hues are lifted in luminance so
  // they keep ≥4.5:1 against a near-black ground.
  // ───────────────────────────────────────────────────────────────────────

  static const Color darkBackground = Color(0xFF0B0C0B);
  static const Color darkSurface = neutral900;
  static const Color darkSurfaceVariant = neutral800;

  /// One step above [darkSurfaceVariant] — sheets, raised cards.
  static const Color darkSurfaceRaised = Color(0xFF2B2D2A);

  static const Color darkBorder = neutral700;
  static const Color darkDivider = neutral800;

  static const Color darkTextPrimary = neutral50;
  static const Color darkTextSecondary = neutral300;
  static const Color darkTextTertiary = neutral400;

  /// Primary action fill in dark mode — near-black is invisible on a dark
  /// ground, so the action ramp inverts to near-white.
  static const Color darkAction = neutral50;
  static const Color darkActionHover = neutral200;
  static const Color darkTextOnAction = neutral900;

  static const Color darkSuccess = Color(0xFF3BC98B);
  static const Color darkSuccessSurface = Color(0xFF10301F);
  static const Color darkWarning = Color(0xFFE79A2B);
  static const Color darkWarningSurface = Color(0xFF3A2708);
  static const Color darkError = Color(0xFFFF6B5E);
  static const Color darkErrorSurface = Color(0xFF3B1310);
  static const Color darkInfo = Color(0xFF6FA5F5);
  static const Color darkInfoSurface = Color(0xFF122542);

  static const Color darkShimmerBase = neutral800;
  static const Color darkShimmerHighlight = neutral700;

  // ───────────────────────────────────────────────────────────────────────
  // Brightness-aware helpers
  //
  // Widgets that must work in both themes should resolve through these
  // instead of branching on `Theme.of(context).brightness` inline.
  // ───────────────────────────────────────────────────────────────────────

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Success hue legible on the current theme's background.
  static Color successOf(BuildContext context) =>
      _isDark(context) ? darkSuccess : success;

  /// Tinted success background for the current theme.
  static Color successSurfaceOf(BuildContext context) =>
      _isDark(context) ? darkSuccessSurface : successSurface;

  /// Warning hue legible on the current theme's background.
  static Color warningOf(BuildContext context) =>
      _isDark(context) ? darkWarning : warning;

  /// Tinted warning background for the current theme.
  static Color warningSurfaceOf(BuildContext context) =>
      _isDark(context) ? darkWarningSurface : warningSurface;

  /// Error hue legible on the current theme's background.
  static Color errorOf(BuildContext context) =>
      _isDark(context) ? darkError : error;

  /// Tinted error background for the current theme.
  static Color errorSurfaceOf(BuildContext context) =>
      _isDark(context) ? darkErrorSurface : errorSurface;

  /// Info hue legible on the current theme's background.
  static Color infoOf(BuildContext context) =>
      _isDark(context) ? darkInfo : info;

  /// Tinted info background for the current theme.
  static Color infoSurfaceOf(BuildContext context) =>
      _isDark(context) ? darkInfoSurface : infoSurface;

  /// The filled-action colour for the current theme.
  static Color actionOf(BuildContext context) =>
      _isDark(context) ? darkAction : action;

  /// The label colour that sits on top of [actionOf].
  static Color onActionOf(BuildContext context) =>
      _isDark(context) ? darkTextOnAction : textOnDark;

  /// Hairline border colour for the current theme.
  static Color borderOf(BuildContext context) =>
      _isDark(context) ? darkBorder : border;

  /// Card/sheet surface for the current theme.
  static Color surfaceOf(BuildContext context) =>
      _isDark(context) ? darkSurface : surface;

  /// Recessed surface for the current theme.
  static Color surfaceMutedOf(BuildContext context) =>
      _isDark(context) ? darkSurfaceVariant : surfaceMuted;

  /// Skeleton base for the current theme.
  static Color shimmerBaseOf(BuildContext context) =>
      _isDark(context) ? darkShimmerBase : shimmerBase;

  /// Skeleton highlight for the current theme.
  static Color shimmerHighlightOf(BuildContext context) =>
      _isDark(context) ? darkShimmerHighlight : shimmerHighlight;
}

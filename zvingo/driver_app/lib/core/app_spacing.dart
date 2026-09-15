import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Zvingo spacing, radius and elevation tokens — driver surface.
///
/// Normative source: `docs/DESIGN_SYSTEM.md` §3. Identifier names match
/// `consumer_app/lib/core/app_spacing.dart` (§6).
///
/// The scale is a 4pt grid and it is closed: if a value is not on this list it
/// is not a legal gap. Reach for the next token up rather than inventing 18.
class AppSpacing {
  AppSpacing._();

  // ───────────────────────────────────────────────────────────────────────
  // §3.1 Spacing scale — 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64
  // ───────────────────────────────────────────────────────────────────────

  /// 2 — hairline nudges only (icon optical alignment).
  static const double xxs = 2;

  /// 4 — inside a chip, between an icon and its own label.
  static const double xs = 4;

  /// 8 — minimum gap between a label and its control.
  static const double sm = 8;

  /// 12 — gap between cards in a list.
  static const double md = 12;

  /// 16 — screen horizontal padding (mobile) and inner card padding.
  static const double lg = 16;

  /// 20 — roomier card padding, sheet padding.
  static const double xl = 20;

  /// 24 — screen horizontal padding on tablet (≥600).
  static const double xxl = 24;

  /// 32 — gap between sections; desktop screen padding (≥1024).
  static const double section = 32;

  /// 40 — above a sticky footer's primary action.
  static const double xxxl = 40;

  /// 48 — large empty-state breathing room.
  static const double huge = 48;

  /// 64 — hero spacing on otherwise empty screens.
  static const double giant = 64;

  // ── Named roles (§3.1) ─────────────────────────────────────────────────

  /// Screen horizontal padding for the given width: 16 / 24 / 32.
  static double screenPaddingFor(double width) {
    if (width >= 1024) return section;
    if (width >= 600) return xxl;
    return lg;
  }

  /// Screen horizontal padding resolved from the current [MediaQuery].
  static double screenPaddingOf(BuildContext context) =>
      screenPaddingFor(MediaQuery.sizeOf(context).width);

  /// Horizontal-only screen padding, resolved responsively.
  static EdgeInsets screenInsetsOf(BuildContext context) =>
      EdgeInsets.symmetric(horizontal: screenPaddingOf(context));

  /// Gap between cards in a vertical list (12).
  static const double listGap = md;

  /// Gap between major page sections (32).
  static const double sectionGap = section;

  /// Inner padding of a card (16).
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  /// Inner padding of a bottom sheet (20 sides, 8 top under the drag handle).
  static const EdgeInsets sheetPadding =
      EdgeInsets.fromLTRB(xl, sm, xl, xl);

  // ───────────────────────────────────────────────────────────────────────
  // Driver ergonomics
  //
  // The driver app is used one-handed, outdoors, sometimes on a moving
  // vehicle. Primary actions are 56 tall rather than the 52 in §5.1 — see the
  // deviation note in `theme.dart`.
  // ───────────────────────────────────────────────────────────────────────

  /// Height of a primary / secondary / destructive driver button.
  static const double buttonHeight = 56;

  /// Height of a tertiary (text) driver button.
  static const double buttonHeightCompact = 48;

  /// Height of the slide-to-confirm track.
  static const double slideTrackHeight = 68;

  /// Minimum touch target on every surface (§5.1).
  static const double minTouchTarget = 48;

  /// Height of the bottom navigation bar, excluding safe-area inset.
  static const double navBarHeight = 68;

  /// Height of the persistent active-delivery bar in the shell.
  static const double activeDeliveryBarHeight = 64;

  // ───────────────────────────────────────────────────────────────────────
  // §3.2 Radius
  // ───────────────────────────────────────────────────────────────────────

  /// 8 — chips, tags, small badges.
  static const double radiusSm = 8;

  /// 14 — buttons, inputs, small cards.
  static const double radiusMd = 14;

  /// 20 — cards, images, list tiles.
  static const double radiusLg = 20;

  /// 28 — bottom sheets, modals, hero images.
  static const double radiusXl = 28;

  /// 999 — avatars, pills, FABs, toggles.
  static const double radiusFull = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(radiusLg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(radiusXl));
  static const BorderRadius brFull =
      BorderRadius.all(Radius.circular(radiusFull));

  /// Top-only radius for a bottom sheet.
  static const BorderRadius brSheetTop =
      BorderRadius.vertical(top: Radius.circular(radiusXl));

  // ───────────────────────────────────────────────────────────────────────
  // §3.3 Elevation — shadow only, never Material `elevation`.
  //
  // Never stack these. A card at rest is `shadowSm` plus a neutral200
  // hairline; raised or dragged is `shadowMd`; sheets and modals `shadowLg`.
  // ───────────────────────────────────────────────────────────────────────

  /// `0 1px 2px rgba(16,18,16,0.04)` — cards at rest.
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x0A101210),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// `0 8px 24px rgba(16,18,16,0.08)` — raised / dragged / hovered.
  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x14101210),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// `0 20px 48px rgba(16,18,16,0.12)` — sheets and modals.
  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x1F101210),
      blurRadius: 48,
      offset: Offset(0, 20),
    ),
  ];

  /// `0 -4px 24px rgba(16,18,16,0.10)` — bottom nav and sticky footers only.
  static const List<BoxShadow> shadowDock = [
    BoxShadow(
      color: Color(0x1A101210),
      blurRadius: 24,
      offset: Offset(0, -4),
    ),
  ];

  /// No shadow. Use instead of an empty literal so intent is explicit.
  static const List<BoxShadow> shadowNone = <BoxShadow>[];

  // ── Dark-theme shadows ─────────────────────────────────────────────────
  //
  // A 4%-black shadow is invisible on a near-black ground, so dark mode
  // separates surfaces with a deeper shadow plus the border token.

  static const List<BoxShadow> darkShadowSm = [
    BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> darkShadowMd = [
    BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> darkShadowLg = [
    BoxShadow(color: Color(0x73000000), blurRadius: 48, offset: Offset(0, 20)),
  ];

  static const List<BoxShadow> darkShadowDock = [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -4)),
  ];

  /// Resting card shadow for the current theme.
  static List<BoxShadow> shadowSmOf(BuildContext context) =>
      _isDark(context) ? darkShadowSm : shadowSm;

  /// Raised shadow for the current theme.
  static List<BoxShadow> shadowMdOf(BuildContext context) =>
      _isDark(context) ? darkShadowMd : shadowMd;

  /// Sheet/modal shadow for the current theme.
  static List<BoxShadow> shadowLgOf(BuildContext context) =>
      _isDark(context) ? darkShadowLg : shadowLg;

  /// Dock shadow for the current theme.
  static List<BoxShadow> shadowDockOf(BuildContext context) =>
      _isDark(context) ? darkShadowDock : shadowDock;

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // ───────────────────────────────────────────────────────────────────────
  // Composed decorations
  // ───────────────────────────────────────────────────────────────────────

  /// The standard card surface (§5.2): surface fill, `radiusLg`, `shadowSm`
  /// and a 1px hairline border.
  static BoxDecoration cardDecoration(
    BuildContext context, {
    Color? color,
    BorderRadius? radius,
    bool raised = false,
  }) {
    return BoxDecoration(
      color: color ?? AppColors.surfaceOf(context),
      borderRadius: radius ?? brLg,
      border: Border.all(color: AppColors.borderOf(context)),
      boxShadow: raised ? shadowMdOf(context) : shadowSmOf(context),
    );
  }
}

/// Vertical gap tokens, so widget trees read as `Gap.md` rather than
/// `SizedBox(height: 12)`.
class Gap {
  Gap._();

  static const Widget xxs = SizedBox(height: AppSpacing.xxs);
  static const Widget xs = SizedBox(height: AppSpacing.xs);
  static const Widget sm = SizedBox(height: AppSpacing.sm);
  static const Widget md = SizedBox(height: AppSpacing.md);
  static const Widget lg = SizedBox(height: AppSpacing.lg);
  static const Widget xl = SizedBox(height: AppSpacing.xl);
  static const Widget xxl = SizedBox(height: AppSpacing.xxl);
  static const Widget section = SizedBox(height: AppSpacing.section);

  /// Horizontal gaps.
  static const Widget hXs = SizedBox(width: AppSpacing.xs);
  static const Widget hSm = SizedBox(width: AppSpacing.sm);
  static const Widget hMd = SizedBox(width: AppSpacing.md);
  static const Widget hLg = SizedBox(width: AppSpacing.lg);
  static const Widget hXl = SizedBox(width: AppSpacing.xl);
}

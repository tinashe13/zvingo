import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Zvingo spacing, radius and elevation tokens — the Flutter binding of §3 of
/// `docs/DESIGN_SYSTEM.md`.
///
/// The 4pt grid allows **only** these values: 2, 4, 8, 12, 16, 20, 24, 32, 40,
/// 48, 64. Anything else is a magic number and fails review.
///
/// ```dart
/// Padding(
///   padding: const EdgeInsets.all(AppSpacing.md),        // 16
///   child: DecoratedBox(
///     decoration: BoxDecoration(
///       borderRadius: AppRadius.lgAll,                   // 20
///       boxShadow: AppShadows.sm,
///     ),
///   ),
/// )
/// ```
class AppSpacing {
  AppSpacing._();

  /// 2 — hairline nudges only.
  static const double xxxs = 2;

  /// 4 — icon-to-label inside a chip.
  static const double xxs = 4;

  /// 8 — minimum gap between a label and its control.
  static const double xs = 8;

  /// 12 — gap between cards in a list.
  static const double sm = 12;

  /// 16 — screen horizontal padding (mobile) and inner card padding.
  static const double md = 16;

  /// 20 — roomy inner padding.
  static const double lg = 20;

  /// 24 — screen horizontal padding on tablet.
  static const double xl = 24;

  /// 32 — gap between sections; screen padding on desktop.
  static const double xxl = 32;

  /// 40.
  static const double xxxl = 40;

  /// 48 — minimum touch target, large vertical rhythm.
  static const double huge = 48;

  /// 64 — empty-state breathing room.
  static const double giant = 64;

  /// Gap between cards in a vertical list (§3.1).
  static const double listGap = sm;

  /// Gap between major sections of a screen (§3.1).
  static const double sectionGap = xxl;

  /// Inner padding of a card (§3.1).
  static const double cardPadding = md;

  /// Minimum touch target on every interactive surface (§5.1).
  static const double minTapTarget = 48;

  /// Responsive screen horizontal padding: 16 mobile, 24 ≥600, 32 ≥1024.
  static double screenHorizontal(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1024) return xxl;
    if (width >= 600) return xl;
    return md;
  }

  /// Responsive horizontal page padding as [EdgeInsets].
  static EdgeInsets screenPadding(BuildContext context, {double vertical = 0}) {
    return EdgeInsets.symmetric(
      horizontal: screenHorizontal(context),
      vertical: vertical,
    );
  }

  /// A vertical gap of [height] logical pixels.
  static Widget gapV(double height) => SizedBox(height: height);

  /// A horizontal gap of [width] logical pixels.
  static Widget gapH(double width) => SizedBox(width: width);
}

/// Corner radius tokens (§3.2).
class AppRadius {
  AppRadius._();

  /// 8 — chips, tags, small badges.
  static const double sm = 8;

  /// 14 — buttons, inputs, small cards.
  static const double md = 14;

  /// 20 — cards, images, list tiles.
  static const double lg = 20;

  /// 28 — bottom sheets, modals, hero images.
  static const double xl = 28;

  /// 999 — avatars, pills, FABs, toggles.
  static const double full = 999;

  /// `BorderRadius.circular(8)`.
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));

  /// `BorderRadius.circular(14)`.
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));

  /// `BorderRadius.circular(20)`.
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));

  /// `BorderRadius.circular(28)`.
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));

  /// `BorderRadius.circular(999)`.
  static const BorderRadius fullAll = BorderRadius.all(Radius.circular(full));

  /// Top-only 20 radius — for an image sitting at the top of a card.
  static const BorderRadius lgTop =
      BorderRadius.vertical(top: Radius.circular(lg));

  /// Top-only 28 radius — for a bottom sheet.
  static const BorderRadius xlTop =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Elevation tokens (§3.3). Shadow only — **never** Material `elevation`.
///
/// Cards at rest use [sm] plus a `neutral/200` hairline border. Raised,
/// dragged or hovered cards use [md]. Sheets and modals use [lg].
/// **Never stack shadows.**
class AppShadows {
  AppShadows._();

  static const Color _ink = AppColors.neutral900;

  /// `0 1px 2px rgba(16,18,16,0.04)` — cards at rest.
  static final List<BoxShadow> sm = <BoxShadow>[
    BoxShadow(
      color: _ink.withValues(alpha: 0.04),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  /// `0 8px 24px rgba(16,18,16,0.08)` — raised / dragged / hovered.
  static final List<BoxShadow> md = <BoxShadow>[
    BoxShadow(
      color: _ink.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// `0 20px 48px rgba(16,18,16,0.12)` — sheets and modals.
  static final List<BoxShadow> lg = <BoxShadow>[
    BoxShadow(
      color: _ink.withValues(alpha: 0.12),
      blurRadius: 48,
      offset: const Offset(0, 20),
    ),
  ];

  /// `0 -4px 24px rgba(16,18,16,0.10)` — bottom nav and sticky footers only.
  static final List<BoxShadow> dock = <BoxShadow>[
    BoxShadow(
      color: _ink.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, -4),
    ),
  ];

  /// No shadow.
  static const List<BoxShadow> none = <BoxShadow>[];
}

/// The standard card decoration: `neutral/0`, `radius/lg`, `shadow/sm`,
/// 1px `neutral/200` hairline (§5.2).
BoxDecoration zvCardDecoration({
  Color color = AppColors.surface,
  BorderRadius? borderRadius,
  bool raised = false,
  Color borderColor = AppColors.border,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: borderRadius ?? AppRadius.lgAll,
    border: Border.all(color: borderColor),
    boxShadow: raised ? AppShadows.md : AppShadows.sm,
  );
}

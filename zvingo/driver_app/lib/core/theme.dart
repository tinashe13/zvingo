import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Zvingo driver theme.
///
/// Normative source: `docs/DESIGN_SYSTEM.md`. Both [lightTheme] and
/// [darkTheme] are real, fully specified themes — drivers work nights, so dark
/// mode is a first-class surface, not an afterthought. `main.dart` passes both
/// and lets `themeMode: ThemeMode.system` follow the OS setting.
///
/// ## Deliberate deviations from the shared component contract
///
/// * **Button height is 56, not the 52 in §5.1.** Per the driver swarm brief,
///   this app is operated one-handed, outdoors, frequently while the user is
///   still astride a motorbike or sitting in a car, sometimes in the rain and
///   usually in a hurry. Primary actions are therefore enlarged and live in
///   the bottom third of the screen. The 48×48 minimum touch target from §5.1
///   still applies everywhere; 56 is a floor raise, never a reduction.
/// * **Body text floor is 15pt** (the §2 `body` size) rather than allowing
///   13pt `caption` for anything actionable — sunlight legibility.
///
/// Everything else — colour ramp, radii, shadows, motion — follows the design
/// system exactly, and token identifiers match the consumer app (§6).
class AppTheme {
  AppTheme._();

  /// Height of a filled/outlined driver action. See the class doc for why this
  /// is 56 rather than §5.1's 52.
  static const double buttonHeight = AppSpacing.buttonHeight;

  // ───────────────────────────────────────────────────────────────────────
  // Typography
  // ───────────────────────────────────────────────────────────────────────

  /// The §2 family: Inter where it is available on the device or bundled with
  /// the app, Roboto as the documented fallback.
  ///
  /// This app deliberately does **not** fetch fonts at runtime. A driver on
  /// patchy mobile data would get a flash of fallback text on every cold start
  /// and no webfont at all when offline — and offline is exactly when they
  /// most need to read an address. Ship Inter as a bundled asset to make this
  /// token real; until then it resolves to the platform default, which is what
  /// §2 prescribes.
  static const String fontFamily = 'Inter';

  /// Fallback chain used with [fontFamily].
  static const List<String> fontFamilyFallback = ['Roboto'];

  /// Applies Inter over the §2 token scale, tinted for the given brightness.
  static TextTheme _textTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    TextStyle tint(TextStyle style, {bool muted = false}) =>
        style.copyWith(color: muted ? secondary : primary);

    final base = TextTheme(
      displayLarge: tint(AppTextStyles.display),
      displayMedium: tint(AppTextStyles.h1),
      displaySmall: tint(AppTextStyles.h2),
      headlineLarge: tint(AppTextStyles.h1),
      headlineMedium: tint(AppTextStyles.h2),
      headlineSmall: tint(AppTextStyles.h3),
      titleLarge: tint(AppTextStyles.h2),
      titleMedium: tint(AppTextStyles.h3),
      titleSmall: tint(AppTextStyles.bodyStrong),
      bodyLarge: tint(AppTextStyles.body),
      bodyMedium: tint(AppTextStyles.body),
      bodySmall: tint(AppTextStyles.caption, muted: true),
      labelLarge: tint(AppTextStyles.button),
      labelMedium: tint(AppTextStyles.caption, muted: true),
      labelSmall: tint(AppTextStyles.overline, muted: true),
    );

    // `apply` only swaps the family, so every size, weight, line height,
    // letter-spacing and font feature from the token scale survives intact.
    return base.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Light
  // ───────────────────────────────────────────────────────────────────────

  static final ThemeData lightTheme = _build(
    brightness: Brightness.light,
    scheme: const ColorScheme.light(
      primary: AppColors.action,
      onPrimary: AppColors.textOnDark,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.brandGreen,
      onSecondary: AppColors.textOnDark,
      secondaryContainer: AppColors.brandGreenSurface,
      onSecondaryContainer: AppColors.brandGreenDark,
      tertiary: AppColors.warning,
      onTertiary: AppColors.textOnDark,
      tertiaryContainer: AppColors.warningSurface,
      onTertiaryContainer: AppColors.warning,
      error: AppColors.error,
      onError: AppColors.textOnDark,
      errorContainer: AppColors.errorSurface,
      onErrorContainer: AppColors.error,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.neutral0,
      surfaceContainerLow: AppColors.neutral50,
      surfaceContainer: AppColors.neutral100,
      surfaceContainerHigh: AppColors.neutral100,
      surfaceContainerHighest: AppColors.neutral200,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.neutral100,
      inverseSurface: AppColors.neutral900,
      onInverseSurface: AppColors.neutral0,
      shadow: AppColors.neutral900,
      scrim: AppColors.neutral900,
    ),
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceMuted: AppColors.surfaceMuted,
    border: AppColors.border,
    divider: AppColors.divider,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    action: AppColors.action,
    actionHover: AppColors.actionHover,
    actionPressed: AppColors.actionPressed,
    onAction: AppColors.textOnDark,
    error: AppColors.error,
    navUnselected: AppColors.navUnselected,
    statusBarIconBrightness: Brightness.dark,
  );

  // ───────────────────────────────────────────────────────────────────────
  // Dark
  // ───────────────────────────────────────────────────────────────────────

  static final ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme.dark(
      primary: AppColors.darkAction,
      onPrimary: AppColors.darkTextOnAction,
      primaryContainer: AppColors.neutral700,
      onPrimaryContainer: AppColors.neutral50,
      secondary: AppColors.darkSuccess,
      onSecondary: AppColors.neutral900,
      secondaryContainer: AppColors.darkSuccessSurface,
      onSecondaryContainer: AppColors.darkSuccess,
      tertiary: AppColors.darkWarning,
      onTertiary: AppColors.neutral900,
      tertiaryContainer: AppColors.darkWarningSurface,
      onTertiaryContainer: AppColors.darkWarning,
      error: AppColors.darkError,
      onError: AppColors.neutral900,
      errorContainer: AppColors.darkErrorSurface,
      onErrorContainer: AppColors.darkError,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: AppColors.darkSurface,
      surfaceContainer: AppColors.darkSurfaceVariant,
      surfaceContainerHigh: AppColors.darkSurfaceVariant,
      surfaceContainerHighest: AppColors.darkSurfaceRaised,
      onSurfaceVariant: AppColors.darkTextSecondary,
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.neutral800,
      inverseSurface: AppColors.neutral50,
      onInverseSurface: AppColors.neutral900,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceMuted: AppColors.darkSurfaceVariant,
    border: AppColors.darkBorder,
    divider: AppColors.darkDivider,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    action: AppColors.darkAction,
    actionHover: AppColors.darkActionHover,
    actionPressed: AppColors.neutral300,
    onAction: AppColors.darkTextOnAction,
    error: AppColors.darkError,
    navUnselected: AppColors.neutral500,
    statusBarIconBrightness: Brightness.light,
  );

  // ───────────────────────────────────────────────────────────────────────
  // Shared builder — one definition, two palettes, so light and dark can
  // never drift apart.
  // ───────────────────────────────────────────────────────────────────────

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required Color surface,
    required Color surfaceMuted,
    required Color border,
    required Color divider,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required Color action,
    required Color actionHover,
    required Color actionPressed,
    required Color onAction,
    required Color error,
    required Color navUnselected,
    required Brightness statusBarIconBrightness,
  }) {
    final textTheme = _textTheme(brightness);

    WidgetStateProperty<Color?> fill(Color base) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return brightness == Brightness.dark
                ? AppColors.neutral700
                : AppColors.actionDisabledBg;
          }
          if (states.contains(WidgetState.pressed)) return actionPressed;
          if (states.contains(WidgetState.hovered)) return actionHover;
          return base;
        });

    WidgetStateProperty<Color?> label(Color base) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return brightness == Brightness.dark
                ? AppColors.neutral500
                : AppColors.actionDisabledFg;
          }
          return base;
        });

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,

      // Elevation is expressed as a shadow token (§3.3), never as Material
      // elevation, so every surface tint is switched off.
      applyElevationOverlayColor: false,

      // §4.3 page transitions. `AppPageTransitions` slides the incoming page
      // 24px from the right and fades it over `motion/slow`.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZvingoPageTransitionBuilder(),
          TargetPlatform.iOS: ZvingoPageTransitionBuilder(),
          TargetPlatform.linux: ZvingoPageTransitionBuilder(),
          TargetPlatform.macOS: ZvingoPageTransitionBuilder(),
          TargetPlatform.windows: ZvingoPageTransitionBuilder(),
        },
      ),

      // ── App bar ────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.xs,
        iconTheme: IconThemeData(color: textPrimary, size: 24),
        actionsIconTheme: IconThemeData(color: textPrimary, size: 24),
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: statusBarIconBrightness,
          statusBarBrightness: brightness == Brightness.dark
              ? Brightness.dark
              : Brightness.light,
        ),
      ),

      // ── Cards (§5.2) ───────────────────────────────────────────────────
      // `CardThemeData`, not `CardTheme` — the latter is deprecated as a
      // ThemeData field type in Flutter 3.47.
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.brLg,
          side: BorderSide(color: border),
        ),
      ),

      // ── Dialogs ────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brXl),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
      ),

      // ── Bottom sheets (§5.4: visible drag handle, scrim tap closes) ─────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: brightness == Brightness.dark
            ? AppColors.neutral600
            : AppColors.neutral300,
        dragHandleSize: const Size(44, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: AppSpacing.brSheetTop,
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Inputs (§5.3), raised to the 56 driver height ───────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        constraints: const BoxConstraints(minHeight: buttonHeight),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppSpacing.brMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppSpacing.brMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.brMd,
          borderSide: BorderSide(color: action, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.brMd,
          borderSide: BorderSide(color: error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.brMd,
          borderSide: BorderSide(color: error, width: 1.5),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: AppSpacing.brMd,
          borderSide: BorderSide.none,
        ),
        // Labels sit above the field (§5.3) — never a disappearing placeholder.
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelStyle: textTheme.bodyLarge?.copyWith(color: textSecondary),
        hintStyle: textTheme.bodyLarge?.copyWith(color: textTertiary),
        errorStyle: textTheme.bodySmall?.copyWith(color: error),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),

      // ── Buttons (§5.1 with the documented 56 driver height) ─────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: fill(action),
          foregroundColor: label(onAction),
          iconColor: label(onAction),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          minimumSize: const WidgetStatePropertyAll(
            Size(double.infinity, buttonHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          animationDuration: AppMotion.fast,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: fill(action),
          foregroundColor: label(onAction),
          iconColor: label(onAction),
          minimumSize: const WidgetStatePropertyAll(
            Size(double.infinity, buttonHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          animationDuration: AppMotion.fast,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: label(textPrimary),
          iconColor: label(textPrimary),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: border);
            }
            if (states.contains(WidgetState.pressed)) {
              return BorderSide(color: action, width: 1.5);
            }
            return BorderSide(color: border);
          }),
          minimumSize: const WidgetStatePropertyAll(
            Size(double.infinity, buttonHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          animationDuration: AppMotion.fast,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: label(textPrimary),
          iconColor: label(textPrimary),
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AppSpacing.minTouchTarget),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          animationDuration: AppMotion.fast,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: label(textPrimary),
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
          ),
          shape: const WidgetStatePropertyAll(CircleBorder()),
        ),
      ),

      // ── Chips ──────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: action,
        disabledColor: surfaceMuted,
        surfaceTintColor: Colors.transparent,
        checkmarkColor: onAction,
        side: BorderSide.none,
        elevation: 0,
        pressElevation: 0,
        labelStyle: textTheme.labelMedium?.copyWith(color: textPrimary),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: onAction),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brSm),
      ),

      // ── Navigation (§5.4) ──────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        height: AppSpacing.navBarHeight,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppSpacing.brFull,
        ),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? action : navUnselected,
            size: 26,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => (textTheme.labelSmall ?? AppTextStyles.overline).copyWith(
            letterSpacing: 0.1,
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? action : navUnselected,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: action,
        unselectedItemColor: navUnselected,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: textTheme.labelSmall
            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.labelSmall
            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      ),

      // ── Misc surfaces ──────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        minVerticalPadding: AppSpacing.md,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            brightness == Brightness.dark ? AppColors.neutral50 : AppColors.neutral900,
        contentTextStyle: textTheme.bodyLarge?.copyWith(
          color: brightness == Brightness.dark
              ? AppColors.neutral900
              : AppColors.neutral0,
        ),
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brMd),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: action,
        linearTrackColor: surfaceMuted,
        circularTrackColor: surfaceMuted,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.neutral0
              : AppColors.neutral0,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.brandGreen
              : (brightness == Brightness.dark
                  ? AppColors.neutral700
                  : AppColors.neutral300),
        ),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: brightness == Brightness.dark
              ? AppColors.neutral700
              : AppColors.neutral900,
          borderRadius: AppSpacing.brSm,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.neutral0),
      ),

      // Never surface a raw Material tooltip-less icon-only affordance; the
      // ripple stays subtle so the tap-scale in `TapScale` reads as the
      // primary feedback (§4.3).
      splashColor: action.withValues(alpha: 0.06),
      highlightColor: action.withValues(alpha: 0.04),
    );
  }
}

/// §4.3 page transition: the incoming page slides in 24px from the right and
/// fades over `motion/slow`; popping reverses it. Under reduced motion the
/// translation collapses and only the cross-fade remains.
class ZvingoPageTransitionBuilder extends PageTransitionsBuilder {
  const ZvingoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ZvingoPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// The transition widget behind [ZvingoPageTransitionBuilder], exposed so
/// `router.dart` can use the identical motion for `go_router` pages.
class ZvingoPageTransition extends StatelessWidget {
  /// Drives the incoming page.
  final Animation<double> animation;

  /// Drives the outgoing page as it is covered.
  final Animation<double> secondaryAnimation;

  /// The page being transitioned.
  final Widget child;

  const ZvingoPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final slide = AppMotion.offsetOf(context, AppMotion.pageSlideOffset);
    // `drive` rather than `CurvedAnimation`: these are built every frame of a
    // transition, and a CurvedAnimation would need disposing each time.
    final enter = animation.drive(
      CurveTween(curve: AppMotion.curveOf(context, AppMotion.enter)),
    );
    final leave = secondaryAnimation.drive(
      CurveTween(curve: AppMotion.curveOf(context, AppMotion.standard)),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([enter, leave]),
      builder: (context, inner) {
        // Outgoing page drifts a third of the distance the other way, so the
        // stack reads as depth rather than two unrelated slides.
        final dx = slide * (1 - enter.value) - (slide / 3) * leave.value;
        return Opacity(
          opacity: enter.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}

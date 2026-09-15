import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// The single `ThemeData` for the consumer app, assembled entirely from the
/// token layer (`AppColors` / `AppTextStyles` / `AppSpacing` / `AppMotion`).
///
/// Nothing here invents a colour, a radius or a duration — if a value is not
/// in `docs/DESIGN_SYSTEM.md` it does not belong in this file.
class AppTheme {
  AppTheme._();

  /// Height of a primary / secondary / destructive button (§5.1).
  static const double buttonHeight = 52;

  /// Height of a tertiary (text) button (§5.1).
  static const double tertiaryButtonHeight = 44;

  /// Visual size of an icon button (§5.1). Its tap target is still 48×48.
  static const double iconButtonSize = 44;

  /// Height of a text input (§5.3).
  static const double inputHeight = 52;

  static final ColorScheme _colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.actionDefault,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.actionDefault,
    onPrimary: AppColors.textOnDark,
    primaryContainer: AppColors.neutral100,
    onPrimaryContainer: AppColors.textPrimary,
    secondary: AppColors.brandGreen,
    onSecondary: AppColors.textOnDark,
    secondaryContainer: AppColors.brandGreenSurface,
    onSecondaryContainer: AppColors.brandGreenDark,
    tertiary: AppColors.brandLime,
    onTertiary: AppColors.textPrimary,
    tertiaryContainer: AppColors.brandLimeSurface,
    onTertiaryContainer: AppColors.textPrimary,
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
    outlineVariant: AppColors.divider,
    shadow: AppColors.neutral900,
    scrim: AppColors.neutral900,
    inverseSurface: AppColors.neutral800,
    onInverseSurface: AppColors.neutral0,
  );

  /// Material's `TextTheme` mapped onto the Zvingo type scale (§2), so widgets
  /// that read `Theme.of(context).textTheme.*` land on the right token.
  static const TextTheme _textTheme = TextTheme(
    displayLarge: AppTextStyles.display,
    displayMedium: AppTextStyles.display,
    displaySmall: AppTextStyles.h1,
    headlineLarge: AppTextStyles.h1,
    headlineMedium: AppTextStyles.h1,
    headlineSmall: AppTextStyles.h2,
    titleLarge: AppTextStyles.h2,
    titleMedium: AppTextStyles.h3,
    titleSmall: AppTextStyles.h3,
    bodyLarge: AppTextStyles.body,
    bodyMedium: AppTextStyles.body,
    bodySmall: AppTextStyles.caption,
    labelLarge: AppTextStyles.labelLarge,
    labelMedium: AppTextStyles.caption,
    labelSmall: AppTextStyles.overline,
  );

  static OutlineInputBorder _inputBorder(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide:
          width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
    );
  }

  /// The light (and only) Zvingo theme.
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    fontFamily: AppTextStyles.fontFamily,
    textTheme: _textTheme,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
    primaryIconTheme:
        const IconThemeData(color: AppColors.textPrimary, size: 22),

    // §4.3 — forward page transition on every platform.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: ZvPageTransitionsBuilder(),
        TargetPlatform.iOS: ZvPageTransitionsBuilder(),
        TargetPlatform.linux: ZvPageTransitionsBuilder(),
        TargetPlatform.macOS: ZvPageTransitionsBuilder(),
        TargetPlatform.windows: ZvPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZvPageTransitionsBuilder(),
      },
    ),

    // ── App bar ─────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: AppSpacing.xs,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      actionsIconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      titleTextStyle: AppTextStyles.h2,
      toolbarTextStyle: AppTextStyles.body,
    ),

    // ── Card (§5.2) — shadow only, never Material elevation ─────────────
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: AppColors.neutral900.withValues(alpha: 0.04),
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: AppColors.border),
      ),
    ),

    // ── Inputs (§5.3) ───────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMuted,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      border: _inputBorder(AppColors.border, 0),
      enabledBorder: _inputBorder(AppColors.border, 0),
      disabledBorder: _inputBorder(AppColors.border, 0),
      focusedBorder: _inputBorder(AppColors.actionDefault, 1.5),
      errorBorder: _inputBorder(AppColors.error, 1.5),
      focusedErrorBorder: _inputBorder(AppColors.error, 1.5),
      labelStyle: AppTextStyles.caption,
      floatingLabelStyle:
          AppTextStyles.caption.copyWith(color: AppColors.actionDefault),
      hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
      helperStyle: AppTextStyles.caption,
      errorStyle: AppTextStyles.caption.copyWith(color: AppColors.error),
      errorMaxLines: 3,
      prefixIconColor: AppColors.textSecondary,
      suffixIconColor: AppColors.textSecondary,
    ),

    // ── Buttons (§5.1) ──────────────────────────────────────────────────
    // Primary: action/default fill, neutral/0 label, no border, h52, r14.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.actionDisabledBg;
          }
          if (states.contains(WidgetState.pressed)) {
            return AppColors.actionPressed;
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.actionHover;
          }
          return AppColors.actionDefault;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? AppColors.actionDisabledFg
                : AppColors.textOnDark),
        overlayColor: WidgetStatePropertyAll(
          AppColors.neutral0.withValues(alpha: 0.08),
        ),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSpacing.minTapTarget, buttonHeight),
        ),
        textStyle: const WidgetStatePropertyAll(AppTextStyles.button),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),

    // Secondary: transparent fill, neutral/900 label, 1px neutral/200, h52.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? AppColors.actionDisabledFg
                : AppColors.textPrimary),
        overlayColor: WidgetStatePropertyAll(
          AppColors.neutral900.withValues(alpha: 0.04),
        ),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? AppColors.actionDisabledBg
                  : states.contains(WidgetState.focused)
                      ? AppColors.actionDefault
                      : AppColors.border,
            )),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSpacing.minTapTarget, buttonHeight),
        ),
        textStyle: const WidgetStatePropertyAll(AppTextStyles.button),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),

    // Tertiary: transparent fill, neutral/900 label, no border, h44.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? AppColors.actionDisabledFg
                : AppColors.textPrimary),
        overlayColor: WidgetStatePropertyAll(
          AppColors.neutral900.withValues(alpha: 0.04),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSpacing.minTapTarget, tertiaryButtonHeight),
        ),
        textStyle: const WidgetStatePropertyAll(AppTextStyles.button),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? AppColors.actionDisabledBg
                : AppColors.actionDefault),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? AppColors.actionDisabledFg
                : AppColors.textOnDark),
        elevation: const WidgetStatePropertyAll(0),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSpacing.minTapTarget, buttonHeight),
        ),
        textStyle: const WidgetStatePropertyAll(AppTextStyles.button),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),

    // Icon: neutral/900 glyph on a 48×48 tap target, circular ink.
    // The §5.1 *filled* icon variant (neutral/100 fill, 44×44, radius/full)
    // is `ZvIconButton` in the shared library — it is opt-in so that bare
    // `IconButton`s in app bars and input suffixes stay chrome-free.
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? AppColors.actionDisabledFg
                : AppColors.textPrimary),
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? AppColors.actionDisabledFg
                : AppColors.textPrimary),
        overlayColor: WidgetStatePropertyAll(
          AppColors.neutral900.withValues(alpha: 0.06),
        ),
        iconSize: const WidgetStatePropertyAll(22),
        shape: const WidgetStatePropertyAll(CircleBorder()),
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.actionDefault,
      foregroundColor: AppColors.textOnDark,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: CircleBorder(),
    ),

    // ── Bottom navigation (§5.4) ────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: AppColors.neutral900.withValues(alpha: 0.10),
      indicatorColor: AppColors.surfaceMuted,
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.navSelected
              : AppColors.navUnselected,
          size: 23,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => AppTextStyles.caption.copyWith(
          fontSize: 11,
          height: 14 / 11,
          color: states.contains(WidgetState.selected)
              ? AppColors.navSelected
              : AppColors.navUnselected,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    ),

    // ── Bottom sheet (§5.4: visible drag handle, closes on scrim tap) ────
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.surface,
      modalBarrierColor: AppColors.neutral900.withValues(alpha: 0.45),
      showDragHandle: true,
      dragHandleColor: AppColors.neutral300,
      dragHandleSize: const Size(40, 4),
      elevation: 0,
      modalElevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlTop),
    ),

    // ── Dialog ──────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: AppColors.neutral900.withValues(alpha: 0.45),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      titleTextStyle: AppTextStyles.h2,
      contentTextStyle: AppTextStyles.body,
    ),

    // ── Snackbar ────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.neutral800,
      contentTextStyle:
          AppTextStyles.body.copyWith(color: AppColors.textOnDark),
      actionTextColor: AppColors.brandLime,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      showCloseIcon: false,
    ),

    // ── Divider ─────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),

    // ── Chip ────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceMuted,
      selectedColor: AppColors.actionDefault,
      disabledColor: AppColors.neutral100,
      surfaceTintColor: Colors.transparent,
      checkmarkColor: AppColors.textOnDark,
      elevation: 0,
      pressElevation: 0,
      labelStyle: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
      secondaryLabelStyle:
          AppTextStyles.caption.copyWith(color: AppColors.textOnDark),
      shape: const StadiumBorder(),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
    ),

    // ── List tile ───────────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxxs,
      ),
      iconColor: AppColors.textPrimary,
      textColor: AppColors.textPrimary,
      titleTextStyle: AppTextStyles.h3,
      subtitleTextStyle: AppTextStyles.caption,
      leadingAndTrailingTextStyle: AppTextStyles.caption,
      minLeadingWidth: AppSpacing.xl,
      minVerticalPadding: AppSpacing.sm,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
    ),

    // ── Segmented button ────────────────────────────────────────────────
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.actionDefault
                : AppColors.surfaceMuted),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.textOnDark
                : AppColors.textPrimary),
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.textOnDark
                : AppColors.textPrimary),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSpacing.minTapTarget, tertiaryButtonHeight),
        ),
        textStyle: const WidgetStatePropertyAll(AppTextStyles.button),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),

    // ── Progress ────────────────────────────────────────────────────────
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.actionDefault,
      linearTrackColor: AppColors.neutral200,
      circularTrackColor: AppColors.neutral200,
      linearMinHeight: 4,
      strokeWidth: 2.5,
      strokeCap: StrokeCap.round,
    ),

    // ── Tooltip ─────────────────────────────────────────────────────────
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(
        color: AppColors.neutral800,
        borderRadius: AppRadius.smAll,
      ),
      textStyle: AppTextStyles.caption.copyWith(color: AppColors.textOnDark),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      waitDuration: AppMotion.slow,
      showDuration: AppMotion.deliberate,
      preferBelow: false,
    ),

    // ── Switches / checkboxes / radios ──────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.neutral0
              : AppColors.neutral0),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.actionDisabledBg;
        }
        return states.contains(WidgetState.selected)
            ? AppColors.actionDefault
            : AppColors.neutral300;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.actionDefault
              : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(AppColors.textOnDark),
      side: const BorderSide(color: AppColors.neutral300, width: 1.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.actionDefault
              : AppColors.neutral300),
    ),

    // ── Misc ────────────────────────────────────────────────────────────
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.textPrimary,
      unselectedLabelColor: AppColors.textTertiary,
      labelStyle: AppTextStyles.button,
      unselectedLabelStyle: AppTextStyles.body,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.actionDefault, width: 2),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: AppColors.border),
      ),
      textStyle: AppTextStyles.body,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.actionDefault,
      inactiveTrackColor: AppColors.neutral200,
      thumbColor: AppColors.actionDefault,
      overlayColor: Colors.transparent,
      trackHeight: 4,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        AppColors.neutral400.withValues(alpha: 0.6),
      ),
      radius: const Radius.circular(AppRadius.full),
      thickness: const WidgetStatePropertyAll(4),
    ),
  );
}

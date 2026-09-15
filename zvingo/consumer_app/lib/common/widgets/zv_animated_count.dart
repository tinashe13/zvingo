import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/core/app_text_styles.dart';

/// Animates a numeric value as it changes, counting between the old and new
/// value over `motion/base` (§4.3: "number changes animate by counting /
/// cross-fading — never hard-swap").
///
/// Always renders with tabular figures so the text does not jitter while the
/// digits roll. Under reduced motion the value cross-fades instead.
///
/// ```dart
/// // Cart total
/// ZvAnimatedCount.money(value: cart.total, currency: r'$')
///
/// // Live ETA
/// ZvAnimatedCount(value: etaMinutes, suffix: ' min', decimals: 0)
///
/// // Item count
/// ZvAnimatedCount(value: itemCount.toDouble(), decimals: 0, suffix: ' items')
/// ```
class ZvAnimatedCount extends StatelessWidget {
  const ZvAnimatedCount({
    super.key,
    required this.value,
    this.decimals = 0,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = AppMotion.base,
    this.textAlign,
    this.formatter,
    this.semanticLabel,
  });

  /// Money variant: renders `currency` + a thousands-grouped, 2-decimal value
  /// in `AppTextStyles.money`.
  ///
  /// Zimbabwe is multi-currency (USD, ZIG, ZAR), so [currency] is required —
  /// money is never shown without an explicit symbol.
  const ZvAnimatedCount.money({
    super.key,
    required this.value,
    required String currency,
    this.style,
    this.duration = AppMotion.base,
    this.textAlign,
    this.semanticLabel,
  })  : decimals = 2,
        prefix = currency,
        suffix = '',
        formatter = _moneyFormat;

  /// The current value. Changing it animates from the previous value.
  final double value;

  /// Decimal places to render.
  final int decimals;

  /// Text before the number, e.g. a currency symbol.
  final String prefix;

  /// Text after the number, e.g. " min".
  final String suffix;

  /// Overrides the text style. Tabular figures are forced on regardless.
  final TextStyle? style;

  /// How long the count takes.
  final Duration duration;

  /// Horizontal alignment.
  final TextAlign? textAlign;

  /// Custom number formatter. Receives the interpolated value.
  final String Function(double value)? formatter;

  /// Screen-reader label. Defaults to the rendered string.
  final String? semanticLabel;

  static final NumberFormat _money = NumberFormat('#,##0.00');

  static String _moneyFormat(double v) => _money.format(v);

  String _render(double v) {
    if (formatter != null) return '$prefix${formatter!(v)}$suffix';
    return '$prefix${v.toStringAsFixed(decimals)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final resolved = AppTextStyles.tabular(
      style ?? (decimals > 0 ? AppTextStyles.money : AppTextStyles.bodyStrong),
    );
    final target = _render(value);

    return Semantics(
      label: semanticLabel ?? target,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: value, end: value),
        duration: context.motion(duration),
        curve: context.motionCurve(AppMotion.standard),
        builder: (context, animated, _) {
          return Text(
            _render(animated),
            style: resolved,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        },
      ),
    );
  }
}

/// Cross-fades between two arbitrary widgets when the value behind them
/// changes — for values that are not numeric, such as a status label or a
/// formatted ETA window ("25–35 min").
///
/// ```dart
/// ZvAnimatedSwap(
///   valueKey: order.state,
///   child: Text(order.stateLabel, style: AppTextStyles.bodyStrong),
/// )
/// ```
class ZvAnimatedSwap extends StatelessWidget {
  const ZvAnimatedSwap({
    super.key,
    required this.valueKey,
    required this.child,
    this.duration = AppMotion.base,
    this.alignment = Alignment.centerLeft,
  });

  /// Changing this triggers the cross-fade.
  final Object valueKey;

  /// The content to show for the current [valueKey].
  final Widget child;

  /// Cross-fade duration.
  final Duration duration;

  /// Alignment of the stacked children during the fade.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(duration),
      switchInCurve: context.motionCurve(AppMotion.enter),
      switchOutCurve: context.motionCurve(AppMotion.exit),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: KeyedSubtree(key: ValueKey<Object>(valueKey), child: child),
    );
  }
}

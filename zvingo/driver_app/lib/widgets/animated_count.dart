import 'package:flutter/material.dart';

import '../core/app_motion.dart';
import '../core/app_text_styles.dart';

/// A number that counts to its new value instead of hard-swapping (§4.3).
///
/// Built for live driver earnings: when a delivery completes and the day's
/// total jumps from $18.40 to $23.65, the digits roll up over `motion/base`,
/// which reads as *money arriving* rather than as the screen glitching.
///
/// The style must use tabular figures or the number will jitter as it counts —
/// [AppTextStyles.money], [AppTextStyles.moneyLarge] and
/// [AppTextStyles.moneyHero] all do, and are the intended styles here.
///
/// Under reduced motion it cross-fades over `motion/fast` instead of counting.
///
/// ```dart
/// AnimatedCount.currency(
///   cents: state.todayEarningsCents,
///   style: AppTextStyles.moneyHero,
/// )
/// ```
class AnimatedCount extends StatelessWidget {
  /// Target value.
  final double value;

  /// Formats the interpolated value into the string that is rendered.
  final String Function(double value) formatter;

  /// Text style. Should carry tabular figures.
  final TextStyle style;

  /// Animation duration. Defaults to `motion/base`.
  final Duration duration;

  /// Horizontal alignment of the rendered text.
  final TextAlign? textAlign;

  const AnimatedCount({
    super.key,
    required this.value,
    required this.formatter,
    this.style = AppTextStyles.money,
    this.duration = AppMotion.base,
    this.textAlign,
  });

  /// Counts an integer cent amount as currency, e.g. `2365` → `$23.65`.
  ///
  /// [symbol] defaults to `$` (USD is Zvingo's primary currency); pass `ZiG `
  /// or `R` for the other supported currencies. Money always renders with an
  /// explicit symbol.
  factory AnimatedCount.currency({
    Key? key,
    required int cents,
    String symbol = r'$',
    TextStyle style = AppTextStyles.money,
    Duration duration = AppMotion.base,
    TextAlign? textAlign,
  }) {
    return AnimatedCount(
      key: key,
      value: cents / 100,
      formatter: (v) => '$symbol${v.toStringAsFixed(2)}',
      style: style,
      duration: duration,
      textAlign: textAlign,
    );
  }

  /// Counts a whole number, e.g. trips completed today.
  factory AnimatedCount.whole({
    Key? key,
    required int value,
    String suffix = '',
    TextStyle style = AppTextStyles.money,
    Duration duration = AppMotion.base,
    TextAlign? textAlign,
  }) {
    return AnimatedCount(
      key: key,
      value: value.toDouble(),
      formatter: (v) => '${v.round()}$suffix',
      style: style,
      duration: duration,
      textAlign: textAlign,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = formatter(value);

    // Reduced motion: no rolling digits, just a cross-fade to the new value.
    if (AppMotion.reduced(context)) {
      return AnimatedSwitcher(
        duration: AppMotion.fast,
        child: Text(
          text,
          key: ValueKey(text),
          style: AppTextStyles.onSurface(context, style),
          textAlign: textAlign,
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: value, end: value),
      duration: duration,
      curve: AppMotion.standard,
      builder: (context, animated, _) => Text(
        formatter(animated),
        style: AppTextStyles.onSurface(context, style),
        textAlign: textAlign,
      ),
    );
  }
}

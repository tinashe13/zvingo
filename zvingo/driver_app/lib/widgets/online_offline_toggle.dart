import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'confirm_sheet.dart';
import 'tap_scale.dart';

/// The single most consequential control in the driver app: online means
/// offers arrive, offline means they do not.
///
/// It is deliberately large (at least 72pt tall, full width), states its mode
/// in words as well as colour, and is unmistakable at a glance from a metre
/// away in sunlight.
///
/// Three safety behaviours are built in:
/// * **Going offline mid-delivery is blocked.** Pass [hasActiveDelivery] and
///   the control refuses, explaining in plain language that the current
///   delivery has to be finished first. It never silently does nothing.
/// * **Going offline always confirms.** A [ConfirmSheet] names the
///   consequence, because a mis-tap here costs the driver income.
/// * **Going online never confirms.** Friction belongs on the way out, not on
///   the way in.
///
/// ```dart
/// OnlineOfflineToggle(
///   isOnline: home.isDashing,
///   isBusy: home.isSubmitting,
///   hasActiveDelivery: delivery.hasActiveDelivery,
///   onChanged: (next) => ref.read(homeProvider.notifier).setDashing(next),
///   onlineSubtitle: 'Listening for offers in ${home.selectedZone}',
///   offlineSubtitle: "You won't receive offers",
/// )
/// ```
class OnlineOfflineToggle extends StatelessWidget {
  /// Whether the driver is currently accepting offers.
  final bool isOnline;

  /// Called with the requested new state once any confirmation has passed.
  final ValueChanged<bool> onChanged;

  /// Shows a spinner and blocks interaction while the change is in flight.
  final bool isBusy;

  /// When true, going offline is refused with an explanation.
  final bool hasActiveDelivery;

  /// Supporting line shown while online.
  final String onlineSubtitle;

  /// Supporting line shown while offline.
  final String offlineSubtitle;

  const OnlineOfflineToggle({
    super.key,
    required this.isOnline,
    required this.onChanged,
    this.isBusy = false,
    this.hasActiveDelivery = false,
    this.onlineSubtitle = 'Offers will come through here',
    this.offlineSubtitle = "You won't receive offers",
  });

  Future<void> _handleTap(BuildContext context) async {
    if (isBusy) return;

    if (isOnline) {
      // Blocked mid-delivery — explain, don't just refuse.
      if (hasActiveDelivery) {
        HapticFeedback.heavyImpact();
        await ConfirmSheet.show(
          context,
          title: "Finish this delivery first",
          consequence:
              "You're in the middle of a delivery. Complete or hand it back "
              'before going offline so the customer is not left waiting.',
          confirmLabel: 'Got it',
          cancelLabel: 'Back to delivery',
          destructive: false,
          icon: Icons.delivery_dining_rounded,
        );
        return;
      }

      final confirmed = await ConfirmSheet.show(
        context,
        title: 'Go offline?',
        consequence:
            "You'll stop receiving delivery offers until you go back online. "
            'Any offer already on screen will expire.',
        confirmLabel: 'Go offline',
        icon: Icons.pause_circle_outline_rounded,
      );
      if (confirmed) {
        HapticFeedback.mediumImpact();
        onChanged(false);
      }
      return;
    }

    HapticFeedback.mediumImpact();
    onChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final online = isOnline;

    final fill = online
        ? AppColors.successOf(context)
        : (isDark ? AppColors.darkSurfaceVariant : AppColors.neutral100);
    final onFill = online
        ? (isDark ? AppColors.neutral900 : AppColors.textOnDark)
        : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary);
    final subtitleColor = online
        ? onFill.withValues(alpha: 0.78)
        : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary);

    return Semantics(
      toggled: online,
      label: online ? 'You are online' : 'You are offline',
      hint: online ? 'Double tap to go offline' : 'Double tap to go online',
      child: TapScale(
        onTap: isBusy ? null : () => _handleTap(context),
        enforceMinTarget: false,
        haptic: false,
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.base),
          curve: AppMotion.standard,
          // A minimum, not a fixed height: at 200% text scale two lines of
          // copy need more than 72pt and the control must grow, not clip.
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppSpacing.brXl,
            border: online
                ? null
                : Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              _PowerGlyph(online: online, color: onFill),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online ? 'Online' : 'Offline',
                      style: AppTextStyles.h2.copyWith(color: onFill),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      online ? onlineSubtitle : offlineSubtitle,
                      style: AppTextStyles.caption
                          .copyWith(color: subtitleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (isBusy)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(onFill),
                  ),
                )
              else
                _Switch(online: online, onFill: onFill),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulsing power icon — the pulse is the "we are listening" signal, and it
/// only runs while online and while motion is allowed.
class _PowerGlyph extends StatefulWidget {
  final bool online;
  final Color color;

  const _PowerGlyph({required this.online, required this.color});

  @override
  State<_PowerGlyph> createState() => _PowerGlyphState();
}

class _PowerGlyphState extends State<_PowerGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PowerGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.online != widget.online) _sync();
  }

  void _sync() {
    if (widget.online && !AppMotion.reduced(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.online)
                Container(
                  width: 28 + 16 * t,
                  height: 28 + 16 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.22 * (1 - t)),
                  ),
                ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.16),
                ),
                child: Icon(
                  widget.online
                      ? Icons.bolt_rounded
                      : Icons.power_settings_new_rounded,
                  size: 22,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The track/thumb affordance on the right of the toggle. Purely decorative —
/// the whole row is the hit target, so this never needs its own gesture.
class _Switch extends StatelessWidget {
  final bool online;
  final Color onFill;

  const _Switch({required this.online, required this.onFill});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.fast),
      curve: AppMotion.standard,
      width: 56,
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onFill.withValues(alpha: 0.18),
        borderRadius: AppSpacing.brFull,
      ),
      child: AnimatedAlign(
        duration: AppMotion.durationOf(context, AppMotion.fast),
        curve: AppMotion.standard,
        alignment: online ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: onFill,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

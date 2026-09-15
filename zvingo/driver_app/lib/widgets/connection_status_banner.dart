import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'tap_scale.dart';

/// State of the driver app's realtime link to dispatch.
///
/// The driver app holds a WebSocket to the backend; a dropped socket means
/// missed offers, which means lost income. That has to be visible, but it must
/// never block the screen — the driver may be mid-delivery.
enum ConnectionStatus {
  /// Socket is open and subscribed. Nothing is shown.
  connected,

  /// Socket dropped, a reconnect is in flight.
  reconnecting,

  /// No network at all. Cached content stays readable (§5.5).
  offline,

  /// Reconnect attempts have been exhausted; needs a manual retry.
  failed,
}

/// Non-blocking banner reporting the realtime connection (§5.5).
///
/// Renders nothing at all when [status] is [ConnectionStatus.connected], so it
/// is safe to leave mounted permanently at the top of a screen or inside the
/// app shell. It animates in and out on `motion/base`.
///
/// Wire it to whatever the WebSocket layer exposes:
///
/// ```dart
/// ConnectionStatusBanner(
///   status: ref.watch(connectionStatusProvider),
///   onRetry: () => ref.read(deliveryProvider.notifier).reconnect(),
/// )
/// ```
class ConnectionStatusBanner extends StatelessWidget {
  /// Current realtime status.
  final ConnectionStatus status;

  /// Manual retry, shown as a "Retry" affordance for
  /// [ConnectionStatus.failed] and [ConnectionStatus.offline].
  final VoidCallback? onRetry;

  /// Overrides the default copy for the current [status].
  final String? message;

  const ConnectionStatusBanner({
    super.key,
    required this.status,
    this.onRetry,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.durationOf(context, AppMotion.base),
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: status == ConnectionStatus.connected
          ? const SizedBox(width: double.infinity)
          : _Banner(
              status: status,
              onRetry: onRetry,
              message: message,
            ),
    );
  }
}

class _Banner extends StatelessWidget {
  final ConnectionStatus status;
  final VoidCallback? onRetry;
  final String? message;

  const _Banner({required this.status, this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, IconData icon, String copy) = switch (status) {
      ConnectionStatus.reconnecting => (
          AppColors.warningOf(context),
          AppColors.warningSurfaceOf(context),
          Icons.wifi_tethering_rounded,
          'Reconnecting to dispatch — hold tight, offers may be delayed.',
        ),
      ConnectionStatus.offline => (
          AppColors.warningOf(context),
          AppColors.warningSurfaceOf(context),
          Icons.wifi_off_rounded,
          "You're offline. Your last delivery details are still here.",
        ),
      ConnectionStatus.failed => (
          AppColors.errorOf(context),
          AppColors.errorSurfaceOf(context),
          Icons.cloud_off_rounded,
          "Can't reach dispatch. You won't get new offers until this is fixed.",
        ),
      ConnectionStatus.connected => (
          AppColors.successOf(context),
          AppColors.successSurfaceOf(context),
          Icons.check_circle_rounded,
          'Connected',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (status == ConnectionStatus.reconnecting)
              _Spinner(color: fg)
            else
              Icon(icon, size: 20, color: fg),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message ?? copy,
                style: AppTextStyles.caption.copyWith(color: fg),
              ),
            ),
            if (onRetry != null && status != ConnectionStatus.reconnecting) ...[
              const SizedBox(width: AppSpacing.sm),
              TapScale(
                onTap: onRetry,
                enforceMinTarget: false,
                semanticLabel: 'Retry connection',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  constraints: const BoxConstraints(minHeight: 36),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.14),
                    borderRadius: AppSpacing.brSm,
                  ),
                  child: Text(
                    'Retry',
                    style: AppTextStyles.overline.copyWith(color: fg),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small determinate-free spinner tinted to the banner's tone.
class _Spinner extends StatelessWidget {
  final Color color;

  const _Spinner({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

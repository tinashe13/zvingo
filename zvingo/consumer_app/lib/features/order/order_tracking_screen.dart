/// Live order tracking — the screen a hungry person stares at while they wait.
///
/// Design decisions worth knowing before editing:
///
/// * **The state is the biggest thing on the screen.** The headline uses
///   `display` (32/38/800); the ETA sits under it at `h1`. A glance answers
///   "where is my food" before anything else is read.
/// * **The ETA never lies.** It is produced by [OrderEtaEstimator], which
///   degrades from a smoothed live number, to a range, to "Updating…". It is
///   never a hardcoded "25 min".
/// * **The screen says when it is not live.** [OrderTracker] falls back to
///   polling and the banner explains the degradation (§5.5) rather than
///   leaving a stale number looking fresh.
/// * **Every action here is real.** Cancel, confirm delivery, message the
///   courier, rate the order, view the receipt, reorder — all wired to the
///   backend, all with plain-language failures.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/order/order_chat_sheet.dart';
import 'package:consumer_app/features/order/order_live_map.dart';
import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_providers.dart';
import 'package:consumer_app/features/order/order_rating_sheet.dart';
import 'package:consumer_app/features/order/order_receipt_sheet.dart';
import 'package:consumer_app/features/order/order_timeline.dart';
import 'package:consumer_app/features/order/order_tracking_transport.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  bool _confirming = false;
  bool _cancelling = false;
  bool _reordering = false;

  /// The post-delivery rating prompt fires once per visit, never on a loop.
  bool _ratingPrompted = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orderTrackingProvider(widget.orderId));

    ref.listen<AsyncValue<OrderTrackingState>>(
      orderTrackingProvider(widget.orderId),
      (previous, next) {
        final order = next.valueOrNull?.order;
        if (order == null || !order.isDelivered || _ratingPrompted) return;
        _ratingPrompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybePromptForRating(order);
        });
      },
    );

    final state = async.valueOrNull;
    final order = state?.order;
    final restaurant = order?.merchantId == null
        ? null
        : ref.watch(orderRestaurantProvider(order!.merchantId!)).valueOrNull;

    return ZvScreen(
      title: 'Track order',
      subtitle: restaurant?.name ?? order?.shortReference ?? 'Loading your order',
      fallbackRoute: '/orders',
      actions: [
        if (order != null)
          ZvIconButton(
            icon: Icons.receipt_long_rounded,
            tooltip: 'View receipt',
            onPressed: () => showOrderReceiptSheet(
              context,
              order: order,
              restaurant: restaurant,
            ),
          ),
      ],
      banner: state?.connectionMessage == null
          ? null
          : _ConnectionBanner(
              message: state!.connectionMessage!,
              lastUpdate: state.lastUpdate,
              severe: state.status == OrderConnectionStatus.offline,
              onRetry: () =>
                  ref.read(orderTrackerProvider(widget.orderId)).refreshNow(),
            ),
      footer: order == null ? null : _buildFooter(order, state!),
      child: _buildBody(async, state, order, restaurant),
    );
  }

  // ── Body ────────────────────────────────────────────────────────────────

  Widget _buildBody(
    AsyncValue<OrderTrackingState> async,
    OrderTrackingState? state,
    TrackedOrder? order,
    OrderRestaurant? restaurant,
  ) {
    if (order == null) {
      if (async.hasError || state?.error != null) {
        return ZvErrorState(
          error: async.error ?? state?.error,
          title: "We couldn't load this order",
          onRetry: () {
            ref.invalidate(orderTrackerProvider(widget.orderId));
          },
          secondaryActionLabel: 'Back to orders',
          onSecondaryAction: () => context.go('/orders'),
        );
      }
      return const _TrackingSkeleton();
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(orderTrackerProvider(widget.orderId)).refreshNow(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          if (!order.isCancelled) ...[
            ZvEntrance(
              index: 0,
              child: OrderLiveMap(
                orderId: widget.orderId,
                height: _mapHeight(context),
                topInset: AppSpacing.sm,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          ZvEntrance(
            index: 1,
            child: _HeroStatus(state: state!, order: order),
          ),
          const SizedBox(height: AppSpacing.md),
          ZvEntrance(
            index: 2,
            child: _CourierCard(
              order: order,
              state: state,
              onMessage: () => _openChat(order, restaurant),
              onCall: _callCourier,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ZvEntrance(
            index: 3,
            child: _TimelineCard(orderId: widget.orderId, order: order),
          ),
          const SizedBox(height: AppSpacing.md),
          ZvEntrance(
            index: 4,
            child: _OrderSummaryCard(
              order: order,
              restaurant: restaurant,
              onReceipt: () => showOrderReceiptSheet(
                context,
                order: order,
                restaurant: restaurant,
              ),
            ),
          ),
          if (restaurant != null) ...[
            const SizedBox(height: AppSpacing.md),
            ZvEntrance(
              index: 5,
              child: _RestaurantCard(
                restaurant: restaurant,
                onTap: () => context.push('/restaurant/${restaurant.id}'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          ZvEntrance(index: 6, child: _buildCancelAffordance(order)),
        ],
      ),
    );
  }

  static double _mapHeight(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return (height * 0.30).clamp(190.0, 300.0);
  }

  // ── Footer: exactly one primary action ──────────────────────────────────

  Widget _buildFooter(TrackedOrder order, OrderTrackingState state) {
    if (order.canConfirmDelivery) {
      return ZvStickyFooter(
        child: ZvButton.primary(
          label: "I've got my order",
          icon: Icons.check_circle_outline_rounded,
          loading: _confirming,
          onPressed: _confirming ? null : () => _confirmDelivery(order),
        ),
      );
    }

    if (order.isDelivered) {
      final review = ref.watch(orderReviewProvider(order.id)).valueOrNull;
      if (review == null) {
        return ZvStickyFooter(
          child: ZvButton.primary(
            label: 'Rate your order',
            icon: Icons.star_rounded,
            onPressed: () => _openRating(order),
          ),
        );
      }
      return ZvStickyFooter(
        child: ZvButton.primary(
          label: 'Order this again',
          icon: Icons.refresh_rounded,
          loading: _reordering,
          onPressed: _reordering ? null : () => _reorder(order),
        ),
      );
    }

    if (order.isCancelled) {
      return ZvStickyFooter(
        child: ZvButton.primary(
          label: 'Order this again',
          icon: Icons.refresh_rounded,
          loading: _reordering,
          onPressed: _reordering ? null : () => _reorder(order),
        ),
      );
    }

    final unread = ref.watch(orderChatUnreadProvider(order.id)).valueOrNull ?? 0;
    return ZvStickyFooter(
      child: ZvButton.primary(
        label: unread > 0
            ? 'Open messages ($unread new)'
            : (order.driver == null
                ? 'Message the restaurant'
                : 'Message ${order.driver!.firstName}'),
        icon: Icons.chat_bubble_outline_rounded,
        onPressed: () => _openChat(
          order,
          ref.read(orderRestaurantProvider(order.merchantId ?? '')).valueOrNull,
        ),
      ),
    );
  }

  /// The cancel affordance is never hidden: when cancellation is no longer
  /// possible the button stays, disabled, with the reason beneath it (§5.1).
  Widget _buildCancelAffordance(TrackedOrder order) {
    if (order.isTerminal) {
      return const SizedBox.shrink();
    }
    final cancellable = order.canCancel;
    return ZvButton.secondary(
      label: 'Cancel order',
      icon: Icons.close_rounded,
      loading: _cancelling,
      onPressed: cancellable && !_cancelling ? () => _cancelOrder(order) : null,
      disabledReason: cancellable
          ? null
          : 'Your courier already has this order, so it can no longer be '
              'cancelled here. Message them, or contact support from Help.',
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _confirmDelivery(TrackedOrder order) async {
    setState(() => _confirming = true);
    try {
      await ref.read(orderActionsProvider).confirmDelivery(order.id);
      if (!mounted) return;
      setState(() => _confirming = false);
      _snack('Delivery confirmed. Enjoy your meal.', tone: ZvTone.success);
      final refreshed =
          ref.read(orderTrackerProvider(order.id)).latest?.order ?? order;
      await _maybePromptForRating(refreshed);
    } catch (error) {
      if (!mounted) return;
      setState(() => _confirming = false);
      _snack(
        orderErrorMessage(
          error,
          fallback: "We couldn't confirm that just yet. Please try again.",
        ),
        tone: ZvTone.error,
      );
    }
  }

  Future<void> _cancelOrder(TrackedOrder order) async {
    final amount =
        '${order.currencySymbol}${NumberFormat('#,##0.00').format(order.totalAmount)}';
    final confirmed = await showZvConfirmSheet(
      context,
      title: 'Cancel this order?',
      // §5.4: name the consequence, the amount and the timing — never a bare
      // "Are you sure?".
      consequence: 'The restaurant will stop preparing it and you will be '
          'refunded $amount to the payment method you used. Mobile-money '
          'refunds usually land within 3 working days. This cannot be undone, '
          'and once a courier collects your food it can no longer be '
          'cancelled here.',
      confirmLabel: 'Yes, cancel it',
      cancelLabel: 'Keep my order',
      icon: Icons.cancel_rounded,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(orderActionsProvider).cancel(order.id);
      if (!mounted) return;
      setState(() => _cancelling = false);
      _snack('Order cancelled. Your refund is on its way.', tone: ZvTone.success);
    } catch (error) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      _snack(
        orderErrorMessage(
          error,
          fallback: "We couldn't cancel that order. Please try again.",
        ),
        tone: ZvTone.error,
      );
    }
  }

  Future<void> _reorder(TrackedOrder order) async {
    setState(() => _reordering = true);
    try {
      final newId = await ref.read(orderActionsProvider).reorder(order.id);
      if (!mounted) return;
      setState(() => _reordering = false);
      context.pushReplacement('/order/$newId');
    } catch (error) {
      if (!mounted) return;
      setState(() => _reordering = false);
      _snack(
        orderErrorMessage(
          error,
          fallback: "We couldn't place that order again. Please try again.",
        ),
        tone: ZvTone.error,
      );
    }
  }

  Future<void> _openChat(TrackedOrder order, OrderRestaurant? restaurant) async {
    await showOrderChatSheet(
      context,
      orderId: order.id,
      title: order.driver == null
          ? (restaurant?.name ?? 'Messages')
          : order.driver!.firstName,
      subtitle: order.driver == null
          ? 'Order ${order.shortReference}'
          : 'Your courier · ${order.shortReference}',
      readOnly: order.isTerminal,
    );
  }

  /// Offers the courier's number. There is no dialer dependency in this app, so
  /// the sheet shows the number with a copy action rather than a button that
  /// silently does nothing. Only rendered when the API actually sends a number.
  Future<void> _callCourier(String phone) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => ZvSheet(
        title: 'Call your courier',
        subtitle: 'Tap to copy, then dial from your phone app.',
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ZvCard(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: phone));
              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              _snack('Number copied', tone: ZvTone.success);
            },
            child: Row(
              children: [
                const Icon(Icons.phone_rounded, color: AppColors.textPrimary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    phone,
                    style: AppTextStyles.tabular(AppTextStyles.h3),
                  ),
                ),
                const Icon(Icons.copy_rounded,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRating(TrackedOrder order) async {
    final restaurant = order.merchantId == null
        ? null
        : ref.read(orderRestaurantProvider(order.merchantId!)).valueOrNull;
    final submitted = await showOrderRatingSheet(
      context,
      order: order,
      restaurantName: restaurant?.name,
    );
    if (submitted && mounted) {
      ref.invalidate(orderReviewProvider(order.id));
    }
  }

  /// Prompts for a rating after delivery, but only when the order has not
  /// already been reviewed — the backend allows exactly one review per order.
  Future<void> _maybePromptForRating(TrackedOrder order) async {
    if (!order.isDelivered) return;
    final existing = await ref.read(orderReviewProvider(order.id).future);
    if (!mounted || existing != null) return;
    await _openRating(order);
  }

  void _snack(String message, {ZvTone tone = ZvTone.neutral}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              tone == ZvTone.neutral ? AppColors.actionDefault : tone.foreground,
        ),
      );
  }
}

// ── Hero status ───────────────────────────────────────────────────────────

/// The one-second answer: what is happening, and when will it be here.
class _HeroStatus extends StatelessWidget {
  const _HeroStatus({required this.state, required this.order});

  final OrderTrackingState state;
  final TrackedOrder order;

  @override
  Widget build(BuildContext context) {
    final headline = orderHeadline(
      order.state,
      driverFirstName: order.driver?.firstName,
    );
    final eta = state.eta;

    return ZvCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: headline.surface,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(headline.icon, color: headline.color, size: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ZvStatusChip.orderState(order.state),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // The largest thing on the screen, by design.
          ZvAnimatedSwap(
            valueKey: headline.title,
            child: Text(
              headline.title,
              style: AppTextStyles.display,
              semanticsLabel: 'Order status: ${headline.title}',
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ZvAnimatedSwap(
            valueKey: headline.detail,
            child: Text(
              headline.detail,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ),

          if (eta.hasValue) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            _EtaBlock(eta: eta, stale: state.isStale),
          ],

          if (order.progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ProgressLine(progress: order.progress!),
          ],
        ],
      ),
    );
  }
}

/// The ETA, rendered honestly for each confidence level.
class _EtaBlock extends StatelessWidget {
  const _EtaBlock({required this.eta, required this.stale});

  final OrderEta eta;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final muted = stale && eta.confidence != EtaConfidence.unknown;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eta.confidence == EtaConfidence.unknown
                    ? 'Estimated arrival'
                    : 'Arriving in',
                style:
                    AppTextStyles.overline.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              _EtaValue(eta: eta, muted: muted),
              const SizedBox(height: AppSpacing.xxxs),
              Text(
                muted
                    ? 'Waiting for a fresh update — this may be out of date.'
                    : eta.qualifier,
                style: AppTextStyles.caption.copyWith(
                  color: muted ? AppColors.warning : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Icon(
          muted ? Icons.sync_problem_rounded : Icons.schedule_rounded,
          size: 20,
          color: muted ? AppColors.warning : AppColors.textTertiary,
        ),
      ],
    );
  }
}

class _EtaValue extends StatelessWidget {
  const _EtaValue({required this.eta, required this.muted});

  final OrderEta eta;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.h1.copyWith(
      color: muted ? AppColors.textSecondary : AppColors.textPrimary,
    );

    switch (eta.confidence) {
      case EtaConfidence.precise:
        final minutes = eta.minutes ?? 0;
        if (minutes <= 1) {
          return Text('Any minute now', style: style);
        }
        // §4.3: number changes count, never hard-swap.
        return ZvAnimatedCount(
          value: minutes.toDouble(),
          suffix: ' min',
          style: style,
          semanticLabel: 'Arriving in about $minutes minutes',
        );
      case EtaConfidence.estimated:
      case EtaConfidence.unknown:
      case EtaConfidence.finished:
        return ZvAnimatedSwap(
          valueKey: eta.label,
          child: Text(
            eta.label.isEmpty ? '—' : eta.label,
            style: AppTextStyles.tabular(style),
          ),
        );
    }
  }
}

/// Journey progress. Animates towards the new value rather than jumping.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress),
      duration: context.motion(AppMotion.deliberate),
      curve: context.motionCurve(AppMotion.standard),
      builder: (context, value, _) => ClipRRect(
        borderRadius: AppRadius.fullAll,
        child: LinearProgressIndicator(
          value: value,
          minHeight: 6,
          backgroundColor: AppColors.surfaceMuted,
          valueColor: const AlwaysStoppedAnimation<Color>(
            AppColors.actionDefault,
          ),
        ),
      ),
    );
  }
}

// ── Courier ───────────────────────────────────────────────────────────────

class _CourierCard extends ConsumerWidget {
  const _CourierCard({
    required this.order,
    required this.state,
    required this.onMessage,
    required this.onCall,
  });

  final TrackedOrder order;
  final OrderTrackingState state;
  final VoidCallback onMessage;
  final ValueChanged<String> onCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driver = order.driver;

    if (driver == null) {
      return ZvCard(
        child: Row(
          children: [
            const ZvShimmer(
              child: CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.surfaceMuted,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.isTerminal
                        ? 'No courier was assigned'
                        : 'Finding a courier',
                    style: AppTextStyles.h3,
                  ),
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    order.isTerminal
                        ? 'This order ended before a courier picked it up.'
                        : 'We are matching your order with a courier nearby. '
                            'Their details appear here the moment they accept.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final summary = ref.watch(driverRatingProvider(driver.id)).valueOrNull;
    final unread = ref.watch(orderChatUnreadProvider(order.id)).valueOrNull ?? 0;
    final courierPosition = state.driverPosition;
    final destination = order.destination;
    final distance = (courierPosition != null && destination != null)
        ? formatDistance(metresBetween(courierPosition, destination))
        : null;

    return ZvCard(
      child: Column(
        children: [
          Row(
            children: [
              _CourierAvatar(driver: driver),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.name ?? driver.firstName,
                      style: AppTextStyles.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    ZvMetaRow(
                      items: [
                        if (summary?.hasRating ?? false)
                          ZvMetaItem(
                            icon: Icons.star_rounded,
                            label: summary!.rating!.toStringAsFixed(1),
                            tint: AppColors.rating,
                          ),
                        ZvMetaItem(
                          icon: Icons.delivery_dining_rounded,
                          label: driver.vehicle ?? 'Your courier',
                          tabularFigures: false,
                        ),
                        if (distance != null)
                          ZvMetaItem(
                            icon: Icons.near_me_rounded,
                            label: distance,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ZvIconButton(
                icon: Icons.chat_bubble_rounded,
                tooltip: 'Message ${driver.firstName}',
                badgeCount: unread > 0 ? unread : null,
                onPressed: onMessage,
              ),
              if (driver.phone != null) ...[
                const SizedBox(width: AppSpacing.xs),
                ZvIconButton(
                  icon: Icons.phone_rounded,
                  tooltip: 'Call ${driver.firstName}',
                  onPressed: () => onCall(driver.phone!),
                ),
              ],
            ],
          ),
          if (order.deliveryInstructions != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: const BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                'Your note: ${order.deliveryInstructions}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourierAvatar extends StatelessWidget {
  const _CourierAvatar({required this.driver});

  final TrackedDriver driver;

  @override
  Widget build(BuildContext context) {
    if (driver.photoUrl != null) {
      return ClipOval(
        child: ZvNetworkImage(
          url: driver.photoUrl,
          width: 48,
          height: 48,
          borderRadius: AppRadius.fullAll,
          fallbackIcon: Icons.person_rounded,
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.brandGreenSurface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        driver.initial,
        style: AppTextStyles.h3.copyWith(color: AppColors.brandGreenDark),
      ),
    );
  }
}

// ── Timeline ──────────────────────────────────────────────────────────────

class _TimelineCard extends ConsumerWidget {
  const _TimelineCard({required this.orderId, required this.order});

  final String orderId;
  final TrackedOrder order;

  static final DateFormat _time = DateFormat.Hm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(orderEventsProvider(orderId)).valueOrNull;
    final currentRank = orderStateRank(order.state);

    if (order.isCancelled) {
      return ZvCard(
        color: AppColors.errorSurface,
        borderColor: AppColors.errorSurface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cancel_rounded, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Order cancelled', style: AppTextStyles.h3),
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    'Nothing is on the way. Any payment taken is refunded to '
                    'your original payment method.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    /// Timestamp of the first event at or above a node's rank.
    String? stampFor(int rank) {
      if (events == null) return null;
      for (final event in events) {
        if (orderStateRank(event.state) == rank && event.timestamp != null) {
          return _time.format(event.timestamp!);
        }
      }
      return null;
    }

    return ZvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progress', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < kOrderTimeline.length; i++)
            _TimelineNode(
              step: kOrderTimeline[i],
              currentRank: currentRank,
              isLast: i == kOrderTimeline.length - 1,
              stamp: stampFor(kOrderTimeline[i].rank),
            ),
        ],
      ),
    );
  }
}

/// One timeline node. §4.3: the connector fills and the node scales in over
/// `motion/deliberate` when the order reaches it.
class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.step,
    required this.currentRank,
    required this.isLast,
    required this.stamp,
  });

  final OrderTimelineStep step;
  final int currentRank;
  final bool isLast;
  final String? stamp;

  @override
  Widget build(BuildContext context) {
    final done = currentRank > step.rank;
    final active = currentRank == step.rank;
    final reached = done || active;

    // The connector below an active node fills part-way: the step is under way,
    // not finished.
    final fill = done ? 1.0 : (active ? 0.4 : 0.0);
    final duration = context.motion(AppMotion.deliberate);
    final curve = context.motionCurve(AppMotion.standard);

    final Color nodeColor = done
        ? AppColors.actionDefault
        : (active ? AppColors.brandGreen : AppColors.surfaceMuted);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedScale(
                scale: reached ? 1 : 0.85,
                duration: duration,
                curve: context.motionCurve(AppMotion.spring),
                child: AnimatedContainer(
                  duration: duration,
                  curve: curve,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: nodeColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: reached ? nodeColor : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    done ? Icons.check_rounded : step.icon,
                    size: 15,
                    color: reached
                        ? AppColors.textOnDark
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SizedBox(
                      width: 2,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: fill),
                        duration: duration,
                        curve: curve,
                        builder: (context, value, _) => ColoredBox(
                          color: AppColors.border,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: FractionallySizedBox(
                              heightFactor: value,
                              child: const ColoredBox(
                                color: AppColors.actionDefault,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: AppTextStyles.bodyStrong.copyWith(
                            color: reached
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (stamp != null)
                        Text(
                          stamp!,
                          style: AppTextStyles.tabular(
                            AppTextStyles.caption
                                .copyWith(color: AppColors.textTertiary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    done
                        ? step.doneCopy
                        : (active ? step.activeCopy : step.pendingCopy),
                    style: AppTextStyles.caption.copyWith(
                      color: active
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary cards ─────────────────────────────────────────────────────────

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({
    required this.order,
    required this.restaurant,
    required this.onReceipt,
  });

  final TrackedOrder order;
  final OrderRestaurant? restaurant;
  final VoidCallback onReceipt;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your order ${order.shortReference}',
                    style: AppTextStyles.h3),
              ),
              Text(
                '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${item.quantity}×',
                      style: AppTextStyles.tabular(AppTextStyles.bodyStrong),
                    ),
                  ),
                  Expanded(
                    child: Text(item.name, style: AppTextStyles.body),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${order.currencySymbol}${NumberFormat('#,##0.00').format(item.lineTotal)}',
                    style: AppTextStyles.money,
                  ),
                ],
              ),
            ),
          const Divider(height: AppSpacing.lg),
          Row(
            children: [
              const Expanded(
                child: Text('Total', style: AppTextStyles.bodyStrong),
              ),
              ZvAnimatedCount.money(
                value: order.totalAmount,
                currency: order.currencySymbol,
                style: AppTextStyles.moneyLarge,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: ZvButton.tertiary(
              label: 'View full receipt',
              icon: Icons.receipt_long_rounded,
              onPressed: onReceipt,
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  const _RestaurantCard({required this.restaurant, required this.onTap});

  final OrderRestaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      onTap: onTap,
      semanticLabel: 'Open ${restaurant.name}',
      child: Row(
        children: [
          ZvNetworkImage(
            url: restaurant.imageUrl,
            width: 52,
            height: 52,
            borderRadius: AppRadius.mdAll,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurant.name,
                  style: AppTextStyles.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  restaurant.address ?? 'Tap to see the menu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 22),
        ],
      ),
    );
  }
}

// ── Connection banner ─────────────────────────────────────────────────────

/// Non-blocking strip under the app bar. Says what is wrong and when the
/// screen last had real data — the opposite of failing silently.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.message,
    required this.lastUpdate,
    required this.severe,
    required this.onRetry,
  });

  final String message;
  final DateTime? lastUpdate;
  final bool severe;
  final VoidCallback onRetry;

  String get _ago {
    final last = lastUpdate;
    if (last == null) return '';
    final seconds = DateTime.now().difference(last).inSeconds;
    if (seconds < 45) return ' Updated moments ago.';
    final minutes = (seconds / 60).round();
    return ' Last updated $minutes min ago.';
  }

  @override
  Widget build(BuildContext context) {
    final tone = severe ? ZvTone.error : ZvTone.warning;
    return Material(
      color: tone.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              severe ? Icons.cloud_off_rounded : Icons.sync_rounded,
              size: 18,
              color: tone.foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '$message$_ago',
                style: AppTextStyles.caption.copyWith(color: tone.foreground),
              ),
            ),
            ZvButton.tertiary(label: 'Retry', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────

/// Layout-matched skeleton (§4.3: skeletons, not spinners).
class _TrackingSkeleton extends StatelessWidget {
  const _TrackingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ZvShimmer(
          child: ZvSkeletonBox(
            height: (MediaQuery.sizeOf(context).height * 0.30)
                .clamp(190.0, 300.0),
            radius: AppRadius.xl,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const ZvCard(
          child: ZvShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZvSkeletonBox(height: 30, width: 200, radius: AppRadius.sm),
                SizedBox(height: AppSpacing.sm),
                ZvSkeletonText(lines: 2),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const ZvCard(child: ZvListTileSkeleton()),
        const SizedBox(height: AppSpacing.md),
        const ZvCard(
          child: ZvShimmer(child: ZvSkeletonText(lines: 6, lineHeight: 16)),
        ),
      ],
    );
  }
}

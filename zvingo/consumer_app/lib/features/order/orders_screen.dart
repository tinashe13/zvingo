/// Order history — what is arriving now, and everything that already did.
///
/// Active orders get the live map and a tap into full tracking. Past orders get
/// a receipt, a rating (once, matching the backend's one-review-per-order rule)
/// and **one-tap reorder** via `POST /orders/{id}/reorder`.
///
/// Reorder places a real order immediately, so the confirmation snackbar
/// carries **Undo**, which cancels it while it is still `CREATED` (§5.5:
/// "a snackbar confirmation with Undo where reversible").
library;

/// The order list moved to `order_providers.dart` when it became typed, but
/// `features/account/help_screen.dart` imports it from here. Re-exported so
/// that screen keeps working; it can import `order_providers.dart` directly
/// whenever its owner touches it next.
export 'package:consumer_app/features/order/order_providers.dart'
    show consumerOrdersProvider;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/order/order_live_map.dart';
import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_providers.dart';
import 'package:consumer_app/features/order/order_rating_sheet.dart';
import 'package:consumer_app/features/order/order_receipt_sheet.dart';
import 'package:consumer_app/features/order/order_timeline.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool _showActive = true;
  String? _selectedOrderId;
  String? _busyOrderId;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(consumerOrdersProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppPageTitle(
              eyebrow: 'Your activity',
              title: 'Orders',
              subtitle: 'Track what is arriving and reorder a favourite.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _SegmentedTabs(
                showActive: _showActive,
                onChanged: (value) => setState(() => _showActive = value),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ordersAsync.when(
                loading: () => const _OrdersSkeleton(),
                error: (error, _) => ZvErrorState(
                  error: error,
                  title: "We couldn't load your orders",
                  onRetry: () => ref.invalidate(consumerOrdersProvider),
                ),
                data: (orders) {
                  final filtered = orders
                      .where((o) => _showActive ? o.isActive : o.isTerminal)
                      .toList(growable: false);
                  if (filtered.isEmpty) return _emptyState();
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(consumerOrdersProvider),
                    child: _showActive
                        ? _buildActive(filtered)
                        : _buildPast(filtered),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      // Keeps pull-to-refresh working on an empty list.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.06),
        ZvEmptyState(
          icon: _showActive
              ? Icons.delivery_dining_rounded
              : Icons.receipt_long_rounded,
          title: _showActive ? 'Nothing on the way' : 'No past orders yet',
          message: _showActive
              ? 'When you place an order, live tracking and your courier’s '
                  'position appear right here.'
              : 'Orders you have received or cancelled land here, ready to '
                  'reorder in one tap.',
          actionLabel: _showActive ? 'Find food' : 'Browse restaurants',
          onAction: () => context.go('/home'),
          secondaryActionLabel: _showActive ? 'See past orders' : null,
          onSecondaryAction:
              _showActive ? () => setState(() => _showActive = false) : null,
        ),
      ],
    );
  }

  // ── Active ──────────────────────────────────────────────────────────────

  Widget _buildActive(List<TrackedOrder> orders) {
    final selectedId = orders.any((o) => o.id == _selectedOrderId)
        ? _selectedOrderId!
        : orders.first.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        118,
      ),
      children: [
        ZvEntrance(
          index: 0,
          child: OrderLiveMap(
            key: ValueKey(selectedId),
            orderId: selectedId,
            height: 326,
            onOpenTracking: () => context.push('/order/$selectedId'),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                orders.length == 1 ? 'Current order' : 'Your active orders',
                style: AppTextStyles.h3,
              ),
            ),
            if (orders.length > 1)
              Text(
                'Tap to switch map',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < orders.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.listGap),
            child: ZvEntrance(
              index: i + 1,
              child: _ActiveOrderCard(
                order: orders[i],
                selected: orders[i].id == selectedId,
                // Only the order on the map runs a live tracker: every tracker
                // opens its own event stream, so watching all of them would
                // mean N duplicate connections for one screen.
                live: orders[i].id == selectedId,
                onTap: () {
                  if (orders[i].id == selectedId) {
                    context.push('/order/${orders[i].id}');
                  } else {
                    setState(() => _selectedOrderId = orders[i].id);
                  }
                },
                onTrack: () => context.push('/order/${orders[i].id}'),
              ),
            ),
          ),
      ],
    );
  }

  // ── Past ────────────────────────────────────────────────────────────────

  Widget _buildPast(List<TrackedOrder> orders) {
    return ZvStaggeredListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        118,
      ),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _PastOrderCard(
          order: order,
          busy: _busyOrderId == order.id,
          onOpen: () => context.push('/order/${order.id}'),
          onReceipt: () => _openReceipt(order),
          onReorder: () => _reorder(order),
          onRate: () => _rate(order),
        );
      },
    );
  }

  Future<void> _openReceipt(TrackedOrder order) async {
    final restaurant = order.merchantId == null
        ? null
        : await ref.read(orderRestaurantProvider(order.merchantId!).future);
    if (!mounted) return;
    await showOrderReceiptSheet(context, order: order, restaurant: restaurant);
  }

  Future<void> _rate(TrackedOrder order) async {
    final restaurant = order.merchantId == null
        ? null
        : await ref.read(orderRestaurantProvider(order.merchantId!).future);
    if (!mounted) return;
    final submitted = await showOrderRatingSheet(
      context,
      order: order,
      restaurantName: restaurant?.name,
    );
    if (submitted && mounted) ref.invalidate(orderReviewProvider(order.id));
  }

  /// One tap places the order. The snackbar's Undo cancels it again while it
  /// is still cancellable, so a mis-tap is never a lost US$12.
  Future<void> _reorder(TrackedOrder order) async {
    setState(() => _busyOrderId = order.id);
    try {
      final newId = await ref.read(orderActionsProvider).reorder(order.id);
      if (!mounted) return;
      setState(() => _busyOrderId = null);
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Order placed again · '
              '${order.currencySymbol}${NumberFormat('#,##0.00').format(order.totalAmount)}',
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _undoReorder(newId),
            ),
          ),
        );
      context.push('/order/$newId');
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyOrderId = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              orderErrorMessage(
                error,
                fallback: "We couldn't place that order again. Please try "
                    'again in a moment.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  Future<void> _undoReorder(String orderId) async {
    try {
      await ref.read(orderActionsProvider).cancel(orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Reorder cancelled')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              orderErrorMessage(
                error,
                fallback: 'That order is already being prepared, so it could '
                    'not be undone. Open it to cancel.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }
}

// ── Tabs ──────────────────────────────────────────────────────────────────

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.showActive, required this.onChanged});

  final bool showActive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          _tab(context, 'Active', showActive, () => onChanged(true)),
          _tab(context, 'Past', !showActive, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label orders',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: AnimatedContainer(
            duration: context.motion(AppMotion.fast),
            curve: context.motionCurve(AppMotion.standard),
            height: AppSpacing.minTapTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.actionDefault : Colors.transparent,
              borderRadius: AppRadius.mdAll,
            ),
            child: Text(
              label,
              style: AppTextStyles.button.copyWith(
                color:
                    selected ? AppColors.textOnDark : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────

/// An in-flight order. Reads the live tracker so the headline and ETA on this
/// card match the tracking screen exactly.
class _ActiveOrderCard extends ConsumerWidget {
  const _ActiveOrderCard({
    required this.order,
    required this.selected,
    required this.live,
    required this.onTap,
    required this.onTrack,
  });

  final TrackedOrder order;
  final bool selected;

  /// Whether this card subscribes to the live tracker. Only the card whose
  /// order is on the map does; the rest render the last list snapshot, which
  /// pull-to-refresh updates.
  final bool live;

  final VoidCallback onTap;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracked =
        live ? ref.watch(orderTrackingProvider(order.id)).valueOrNull : null;
    final current = tracked?.order ?? order;
    final headline = orderHeadline(
      current.state,
      driverFirstName: current.driver?.firstName,
    );
    final eta = tracked?.eta;
    final restaurant = current.merchantId == null
        ? null
        : ref.watch(orderRestaurantProvider(current.merchantId!)).valueOrNull;

    return ZvCard(
      onTap: onTap,
      color: selected ? AppColors.surfaceMuted : AppColors.surface,
      semanticLabel:
          '${headline.title}. ${restaurant?.name ?? current.shortReference}. '
          '${selected ? 'Selected. Tap to open tracking' : 'Tap to show on the map'}',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: headline.surface,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(headline.icon, color: headline.color, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZvAnimatedSwap(
                  valueKey: headline.title,
                  child: Text(headline.title, style: AppTextStyles.h3),
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  restaurant?.name ?? current.itemsSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (eta != null &&
                    eta.hasValue &&
                    eta.confidence != EtaConfidence.unknown) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  ZvAnimatedSwap(
                    valueKey: eta.label,
                    child: Text(
                      eta.label,
                      style: AppTextStyles.tabular(
                        AppTextStyles.caption
                            .copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${current.currencySymbol}${NumberFormat('#,##0.00').format(current.totalAmount)}',
                style: AppTextStyles.money,
              ),
              const SizedBox(height: AppSpacing.xs),
              ZvIconButton(
                icon: selected ? Icons.north_east_rounded : Icons.map_outlined,
                tooltip: selected ? 'Open live tracking' : 'Show on the map',
                onPressed: selected ? onTrack : onTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A delivered or cancelled order: receipt, rating, reorder.
class _PastOrderCard extends ConsumerWidget {
  const _PastOrderCard({
    required this.order,
    required this.busy,
    required this.onOpen,
    required this.onReceipt,
    required this.onReorder,
    required this.onRate,
  });

  final TrackedOrder order;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onReceipt;
  final VoidCallback onReorder;
  final VoidCallback onRate;

  static final DateFormat _date = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = order.merchantId == null
        ? null
        : ref.watch(orderRestaurantProvider(order.merchantId!)).valueOrNull;
    final review = order.isDelivered
        ? ref.watch(orderReviewProvider(order.id)).valueOrNull
        : null;
    final placed = order.createdAt;

    return ZvCard(
      onTap: onOpen,
      semanticLabel: 'Order ${order.shortReference}, '
          '${order.isDelivered ? 'delivered' : 'cancelled'}. Tap for details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZvNetworkImage(
                url: restaurant?.imageUrl,
                width: 48,
                height: 48,
                borderRadius: AppRadius.mdAll,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant?.name ?? 'Order ${order.shortReference}',
                      style: AppTextStyles.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      order.itemsSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${order.currencySymbol}${NumberFormat('#,##0.00').format(order.totalAmount)}',
                style: AppTextStyles.money,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              ZvStatusChip.orderState(order.state, compact: true),
              const SizedBox(width: AppSpacing.xs),
              if (placed != null)
                Text(
                  _date.format(placed),
                  style: AppTextStyles.tabular(
                    AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
              if (review != null) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.star_rounded,
                    size: 15, color: AppColors.rating),
                Text(
                  'You rated ${review.restaurantRating}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: ZvButton.secondary(
                  label: 'Reorder',
                  icon: Icons.refresh_rounded,
                  loading: busy,
                  onPressed: busy ? null : onReorder,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ZvIconButton(
                icon: Icons.receipt_long_rounded,
                tooltip: 'View receipt for ${order.shortReference}',
                onPressed: onReceipt,
              ),
              if (order.isDelivered && review == null) ...[
                const SizedBox(width: AppSpacing.xs),
                ZvIconButton(
                  icon: Icons.star_outline_rounded,
                  tooltip: 'Rate order ${order.shortReference}',
                  onPressed: onRate,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Layout-matched loading state (§4.3).
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        118,
      ),
      children: [
        const ZvShimmer(
          child: ZvSkeletonBox(height: 326, radius: AppRadius.xl),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.listGap),
            child: ZvCard(child: ZvListTileSkeleton()),
          ),
      ],
    );
  }
}

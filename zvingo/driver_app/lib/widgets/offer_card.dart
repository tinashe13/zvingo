import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// OfferCard — bottom-sheet style delivery offer panel.
///
/// Designed to sit on top of a full-screen route map (Uber-style).
/// Shows payout with optional tip breakdown, items summary, and route details.
class OfferCard extends StatelessWidget {
  final String merchantName;
  final String merchantAddress;
  final String customerName;
  final String customerAddress;
  final int deliveryFeeCents;
  final int tipCents;
  final int orderSubtotalCents;
  final String itemsSummary;
  final double estimatedDistanceKm;
  final int estimatedTimeMinutes;
  final int remainingSeconds;
  final String paymentMethod;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const OfferCard({
    super.key,
    required this.merchantName,
    required this.merchantAddress,
    this.customerName = 'Customer',
    required this.customerAddress,
    required this.deliveryFeeCents,
    this.tipCents = 0,
    this.orderSubtotalCents = 0,
    this.itemsSummary = '',
    required this.estimatedDistanceKm,
    required this.estimatedTimeMinutes,
    required this.remainingSeconds,
    required this.paymentMethod,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    // Driver receives 85% of the gross delivery fee.
    // Delivery fee is $5 per started 5 km block (e.g. 8 km = 2 blocks = $10 gross).
    final driverEarningsCents = (deliveryFeeCents * 0.85).round();
    final driverDollars = driverEarningsCents ~/ 100;
    final driverCentsStr = (driverEarningsCents % 100).toString().padLeft(2, '0');
    final tipDollars = tipCents ~/ 100;
    final tipCentsStr = (tipCents % 100).toString().padLeft(2, '0');
    final hasTip = tipCents > 0;
    final hasOrderValue = orderSubtotalCents > 0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 32,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ───────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Timer row ─────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Countdown badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              value: remainingSeconds / 45,
                              color: remainingSeconds > 15
                                  ? AppColors.primary
                                  : AppColors.error,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${remainingSeconds}s',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    // Decline button
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        onPressed: onDecline,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Payout breakdown ──────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left: driver earnings + order total
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$$driverDollars.$driverCentsStr',
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'Your earnings',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (hasOrderValue)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Order total: \$${(orderSubtotalCents / 100).toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                      ],
                    ),

                    // Right: tip amount (if any)
                    if (hasTip)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '+\$$tipDollars.$tipCentsStr',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            'tip',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // ── Stats Grid ────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StatItem(
                      icon: Icons.flash_on,
                      value: '${estimatedDistanceKm.toStringAsFixed(1)} km',
                      label: 'Distance',
                    ),
                    _StatItem(
                      icon: Icons.schedule,
                      value: '$estimatedTimeMinutes min',
                      label: 'Est. Time',
                    ),
                    _StatItem(
                      icon: Icons.payments_outlined,
                      value: paymentMethod,
                      label: 'Payment',
                      active: false,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Route Details ─────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RouteRow(
                        isPickup: true,
                        name: merchantName,
                        address: merchantAddress,
                      ),
                      // Items summary under pickup
                      if (itemsSummary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 0, 0),
                          child: Text(
                            itemsSummary,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 14),
                      _RouteRow(
                        isPickup: false,
                        name: customerName,
                        address: customerAddress,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Accept Button ─────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Accept Delivery',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool active;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: active
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _RouteRow extends StatelessWidget {
  final bool isPickup;
  final String name;
  final String address;

  const _RouteRow({
    required this.isPickup,
    required this.name,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isPickup ? AppColors.primary : AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (address.isNotEmpty)
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

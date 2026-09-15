/// The order receipt — what was ordered and exactly what it cost.
///
/// ## An honest receipt
///
/// The `Order` document stores `delivery_fee`, `service_fee`, `tax_amount`,
/// `tip_amount` and `discount_amount`, but neither `GET /orders/{id}` nor the
/// `OrderResponse` model returns them today (see the C3 report's backend-gap
/// list). So the sheet does one of two things and says which:
///
/// * **Itemised** — when the API sends the fee fields, every line is shown.
/// * **Summarised** — otherwise: the subtotal is computed from the order lines,
///   the authoritative `total_amount` is shown as the total, and the residual
///   is labelled "Delivery, service fees and tax" rather than being split into
///   invented numbers.
///
/// Inventing a plausible-looking split would be worse than admitting we only
/// have the total.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_providers.dart';

/// Opens the receipt for [order].
Future<void> showOrderReceiptSheet(
  BuildContext context, {
  required TrackedOrder order,
  OrderRestaurant? restaurant,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) => OrderReceiptSheet(order: order, restaurant: restaurant),
  );
}

/// The receipt body. Prefer [showOrderReceiptSheet].
class OrderReceiptSheet extends StatelessWidget {
  const OrderReceiptSheet({super.key, required this.order, this.restaurant});

  final TrackedOrder order;
  final OrderRestaurant? restaurant;

  static final DateFormat _stamp = DateFormat('d MMM yyyy · HH:mm');

  String _money(double value) =>
      '${order.currencySymbol}${NumberFormat('#,##0.00').format(value)}';

  @override
  Widget build(BuildContext context) {
    final placed = order.createdAt;
    final lines = <Widget>[
      for (final item in order.items)
        _ReceiptLine(
          label: '${item.quantity}× ${item.name}',
          value: _money(item.lineTotal),
          note: item.specialInstructions,
        ),
    ];

    return ZvSheet(
      title: 'Receipt',
      subtitle: [
        order.shortReference,
        if (restaurant != null) restaurant!.name,
        if (placed != null) _stamp.format(placed),
      ].join(' · '),
      footer: ZvButton.secondary(
        label: 'Close',
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            ZvStatusChip.orderState(order.state),
            const SizedBox(height: AppSpacing.md),
            ...lines,
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Divider(height: 1),
            ),
            _ReceiptLine(label: 'Subtotal', value: _money(order.subtotal)),
            if (order.hasFeeBreakdown) ...[
              _ReceiptLine(
                label: order.isPickup ? 'Pickup' : 'Delivery fee',
                value: _money(order.deliveryFee ?? 0),
              ),
              _ReceiptLine(
                label: 'Service fee',
                value: _money(order.serviceFee ?? 0),
              ),
              _ReceiptLine(label: 'Tax', value: _money(order.taxAmount ?? 0)),
              if ((order.tipAmount ?? 0) > 0)
                _ReceiptLine(
                  label: 'Courier tip',
                  value: _money(order.tipAmount ?? 0),
                ),
            ] else if (order.derivedFees > 0)
              _ReceiptLine(
                label: 'Delivery, service fees and tax',
                value: _money(order.derivedFees),
              ),
            if ((order.discountAmount ?? 0) > 0)
              _ReceiptLine(
                label: order.promoCode == null
                    ? 'Discount'
                    : 'Promo ${order.promoCode}',
                value: '−${_money(order.discountAmount ?? 0)}',
                tint: AppColors.brandGreenDark,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text('Total paid', style: AppTextStyles.h3),
                ),
                Text(
                  _money(order.totalAmount),
                  style: AppTextStyles.moneyLarge,
                ),
              ],
            ),
            if (!order.hasFeeBreakdown) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'The total above is the amount charged. Zvingo is rolling out '
                'a line-by-line fee breakdown — until then fees and tax are '
                'shown as one line.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary),
              ),
            ],
            if (order.deliveryInstructions != null) ...[
              const SizedBox(height: AppSpacing.lg),
              const Text('Delivery note', style: AppTextStyles.overline),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                order.deliveryInstructions!,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({
    required this.label,
    required this.value,
    this.note,
    this.tint,
  });

  final String label;
  final String value;
  final String? note;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    color: tint ?? AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                value,
                style: AppTextStyles.money.copyWith(
                  color: tint ?? AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxxs),
              child: Text(
                note!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

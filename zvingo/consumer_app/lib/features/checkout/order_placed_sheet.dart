/// The success moment (§4.3): one deliberate celebration that plays **once**,
/// then hands straight off to tracking.
///
/// It is also the receipt. Everything the customer agreed to is restated here
/// — the reconciled total, how it is being paid, and where it is going — so the
/// first thing after the irreversible tap is confirmation, not a blank screen.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/checkout/order_quote.dart';
import 'package:consumer_app/features/payment/payment_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

/// Show the celebration. Resolves once the customer has moved on.
Future<void> showOrderPlacedSheet(
  BuildContext context, {
  required String orderId,
  required OrderQuote quote,
  required PaymentMethodType method,
  required bool isScheduled,
  required String etaText,
  String? addressLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surface,
    builder: (_) => PopScope(
      canPop: false,
      child: OrderPlacedSheet(
        orderId: orderId,
        quote: quote,
        method: method,
        isScheduled: isScheduled,
        etaText: etaText,
        addressLabel: addressLabel,
      ),
    ),
  );
}

class OrderPlacedSheet extends StatefulWidget {
  const OrderPlacedSheet({
    super.key,
    required this.orderId,
    required this.quote,
    required this.method,
    required this.isScheduled,
    required this.etaText,
    this.addressLabel,
  });

  final String orderId;
  final OrderQuote quote;
  final PaymentMethodType method;
  final bool isScheduled;
  final String etaText;
  final String? addressLabel;

  @override
  State<OrderPlacedSheet> createState() => _OrderPlacedSheetState();
}

class _OrderPlacedSheetState extends State<OrderPlacedSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reduced motion gets the end state, not a bounce.
      if (context.reducedMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final paidNow = widget.method.requiresOnlinePayment;

    return ZvSheet(
      title: widget.isScheduled ? 'Order scheduled' : 'Order placed',
      subtitle: 'Reference ${_shortReference(widget.orderId)}',
      showClose: false,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZvButton.primary(
            label: 'Track your order',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/order/${widget.orderId}');
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          ZvButton.tertiary(
            label: 'Back to browsing',
            fullWidth: true,
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _celebration(),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.isScheduled
                  ? 'We have your order and the restaurant will start it in '
                      'time for your slot.'
                  : 'The restaurant has your order. '
                      'We will find a driver and keep you posted.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            ZvCard(
              color: AppColors.background,
              child: Column(
                children: [
                  _row(
                    icon: Icons.schedule_rounded,
                    label: widget.isScheduled ? 'Scheduled for' : 'Estimated',
                    value: widget.etaText,
                  ),
                  if (widget.addressLabel != null)
                    _row(
                      icon: quote.isPickup
                          ? Icons.storefront_outlined
                          : Icons.place_outlined,
                      label: quote.isPickup ? 'Collect from' : 'Delivering to',
                      value: widget.addressLabel!,
                    ),
                  _row(
                    icon: paidNow
                        ? Icons.smartphone_rounded
                        : Icons.payments_outlined,
                    label: paidNow ? 'Paid with' : 'Pay on arrival',
                    value: widget.method.label,
                  ),
                  const Divider(height: AppSpacing.xl),
                  Row(
                    children: [
                      Text(paidNow ? 'Total paid' : 'Total due',
                          style: AppTextStyles.h3),
                      const Spacer(),
                      Text(quote.total.format(),
                          style: AppTextStyles.moneyLarge),
                    ],
                  ),
                  if (quote.hasDiscount) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'You saved ${quote.discount.format()}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.success),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celebration() {
    final scale = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.spring,
    );
    return SizedBox(
      height: 140,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1).animate(scale),
        child: FadeTransition(
          opacity: _controller,
          child: Lottie.asset(
            'assets/animations/order_confirmed.json',
            repeat: false,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.check_circle_rounded,
                  size: 96, color: AppColors.success),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Text(label,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Order ids are long Mongo ids; the last six characters are what support
  /// and the customer actually read to each other.
  static String _shortReference(String orderId) {
    final trimmed = orderId.trim();
    if (trimmed.length <= 6) return trimmed.toUpperCase();
    return trimmed.substring(trimmed.length - 6).toUpperCase();
  }
}

/// Checkout — where the money is decided.
///
/// Design contract for this screen:
///
/// * **One primary action**, in the sticky footer, whose label carries the
///   exact amount that will be charged.
/// * **The breakdown always reconciles.** Every row comes from one
///   [OrderQuote]; `subtotal + delivery + service + tax + tip - discount`
///   equals the footer total in integer cents, and [OrderQuote.reconciles]
///   is asserted before the button is enabled.
/// * **Nothing is disabled without a reason next to it.** Missing address,
///   closed restaurant, missing phone number — each produces a sentence under
///   the button saying exactly what to do.
/// * **No surprise after the tap.** The order is created with the same fees
///   that are on screen (`total_amount` is the food subtotal; the fee fields
///   are sent alongside, which is what `breakdown_for_order` expects), then the
///   mobile-money prompt is raised in place, with a countdown and a retry.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/core/shell_overlays.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/address/saved_address.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/checkout/checkout_sections.dart';
import 'package:consumer_app/features/checkout/order_placed_sheet.dart';
import 'package:consumer_app/features/checkout/order_placement_provider.dart';
import 'package:consumer_app/features/checkout/order_quote.dart';
import 'package:consumer_app/features/checkout/promo_provider.dart';
import 'package:consumer_app/features/payment/payment_provider.dart';
import 'package:consumer_app/features/payment/payment_widgets.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  /// Kept for route compatibility. A Zvingo cart holds one restaurant, so this
  /// is only used to detect a stale deep link into a cart that has moved on.
  final String? restaurantId;

  const CheckoutScreen({super.key, this.restaurantId});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  static const _instructionOptions = <String>[
    'Leave at door',
    'Hand it to me',
    'Meet me outside',
    'Call when you arrive',
  ];

  final _phoneController = TextEditingController();
  final _promoController = TextEditingController();

  String _deliveryInstructions = 'Hand it to me';
  int _tipIndex = 2; // US$2.00 by default
  Money? _customTip;
  PaymentMethodType _method = PaymentMethodType.ecocash;
  String _settlementCurrency = kDefaultCurrency;
  String? _phoneError;
  bool _submitAttempted = false;
  bool _placedThisSession = false;
  bool _celebrated = false;

  /// The quote as it stood when the order was submitted. The basket is not
  /// cleared until the money settles, but the server owns the discount from
  /// that point on, so the screen keeps showing the figures it committed to.
  OrderQuote? _placedQuote;

  @override
  void dispose() {
    _phoneController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  Money _tip(String currency) =>
      _customTip ?? kTipPresets[_tipIndex].money(currency);

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final owner = ref.watch(cartOwnerProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final location = ref.watch(deliveryLocationNotifierProvider);
    final mode = ref.watch(fulfilmentModeProvider);
    final scheduledAt = ref.watch(scheduledSlotProvider);
    final promo = ref.watch(promoProvider);
    final placement = ref.watch(orderPlacementProvider);
    final payment = ref.watch(paymentProvider);

    if (items.isEmpty && !_placedThisSession) {
      return ZvScreen(
        title: 'Checkout',
        fallbackRoute: '/cart',
        child: ZvEmptyState(
          icon: Icons.shopping_bag_outlined,
          title: 'Nothing to check out',
          message: 'Your cart is empty. Add something first and we will bring '
              'you straight back here.',
          actionLabel: 'Browse restaurants',
          onAction: () => context.go('/home'),
        ),
      );
    }

    final restaurantAsync = owner.id == null
        ? null
        : ref.watch(restaurantDetailProvider(owner.id!));
    final restaurant = restaurantAsync?.valueOrNull;

    final liveQuote = OrderQuote.forCart(
      subtotal: subtotal,
      mode: mode,
      restaurantDeliveryFee: restaurant?.deliveryFeeMoney,
      restaurantLat: restaurant?.latitude,
      restaurantLng: restaurant?.longitude,
      dropoffLat: location?.lat,
      dropoffLng: location?.lng,
      tip: _tip(subtotal.currency),
      discount: promo.discountIn(subtotal.currency),
      freeDeliveryFromPromo: promo.isApplied && promo.freeDelivery,
    );
    final quote = _placedQuote ?? liveQuote;
    assert(quote.reconciles, 'Checkout quote must reconcile to the cent');

    // A promo with a minimum stops qualifying when a line is removed, so the
    // code is re-checked against the server whenever the basket moves rather
    // than being quietly rejected at submission.
    ref.listen<Money>(cartSubtotalProvider, (previous, next) {
      if (previous == null || previous == next) return;
      if (!ref.read(promoProvider).isApplied) return;
      ref.read(promoProvider.notifier).revalidate(subtotal: next);
    });

    // If the basket is edited after an order was created but before it was
    // paid for, the order on the server no longer matches what is on screen.
    // Drop the placement so the next tap creates a fresh, correct order rather
    // than charging for something that has changed underneath it.
    ref.listen<List<CartItem>>(cartProvider, (previous, next) {
      if (_celebrated || previous == null || previous == next) return;
      if (!ref.read(orderPlacementProvider).isPlaced) return;
      ref.read(orderPlacementProvider.notifier).reset();
      ref.read(paymentProvider.notifier).reset();
      setState(() => _placedQuote = null);
    });

    // One listener for the whole screen: when the prompt on the customer's
    // phone settles, celebrate exactly once.
    ref.listen<PaymentSession>(paymentProvider, (previous, next) {
      if (next.phase != PaymentPhase.paid || _celebrated || !mounted) return;
      final placed = ref.read(orderPlacementProvider).result;
      if (placed == null) return;
      _celebrated = true;
      _celebrate(
        placed.primaryOrderId,
        _placedQuote ?? quote,
        restaurant,
        ref.read(deliveryLocationNotifierProvider),
      );
    });

    final blocking = _blockingReason(
      restaurant: restaurant,
      location: location,
      mode: mode,
      quote: quote,
      scheduledAt: scheduledAt,
    );

    return ZvScreen(
      title: 'Checkout',
      subtitle: owner.name,
      fallbackRoute: '/cart',
      footer: ZvStickyFooter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (payment.phase == PaymentPhase.awaitingCustomer) ...[
              PaymentWaitingPanel(
                session: payment,
                onCancel: () =>
                    ref.read(paymentProvider.notifier).cancelWaiting(),
              ),
              const SizedBox(height: AppSpacing.sm),
            ] else if (payment.phase == PaymentPhase.failed &&
                payment.failureReason != null) ...[
              PaymentFailurePanel(
                reason: payment.failureReason!,
                onRetry: _retryPayment,
                secondaryLabel: 'Pay another way',
                onSecondary: _openPaymentScreen,
              ),
              const SizedBox(height: AppSpacing.sm),
            ] else if (placement.hasFailed && placement.error != null) ...[
              PaymentFailurePanel(
                reason: placement.error!,
                onRetry: () => _placeOrder(quote, location, restaurant),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    _method.requiresOnlinePayment
                        ? 'You pay now with ${_method.label}'
                        : 'You pay the driver on arrival',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
                ZvAnimatedCount.money(
                  value: quote.total.major,
                  currency: quote.total.symbol,
                  style: AppTextStyles.moneyLarge,
                  semanticLabel: 'Order total',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ZvButton.primary(
              label: _primaryLabel(quote, scheduledAt),
              loading: placement.isPlacing ||
                  payment.phase == PaymentPhase.initiating,
              onPressed: blocking != null ||
                      payment.phase == PaymentPhase.awaitingCustomer
                  ? null
                  : () => _placeOrder(quote, location, restaurant),
              disabledReason: payment.phase == PaymentPhase.awaitingCustomer
                  ? 'Waiting for you to approve the payment on your phone.'
                  : blocking,
            ),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          if (placement.isPlaced && !_placedThisSession)
            const CheckoutNotice(
              tone: ZvTone.info,
              icon: Icons.receipt_long_rounded,
              title: 'This order is already created',
              message:
                  'It is waiting for payment. Paying below finishes the same '
                  'order — it will not be placed twice.',
            ),
          if (restaurantAsync != null && restaurantAsync.isLoading)
            const ZvSkeletonBox(height: 64, radius: AppRadius.lg)
          else if (restaurant != null && !restaurant.isOpen)
            CheckoutNotice(
              tone: ZvTone.warning,
              icon: Icons.schedule_rounded,
              title: restaurant.availability.label,
              message:
                  '${restaurant.name} is not accepting orders right now. Your '
                  'cart is saved — try again when it reopens.',
            ),
          FulfilmentSection(
            mode: mode,
            restaurant: restaurant,
            location: location,
            scheduledAt: scheduledAt,
            instructions: _deliveryInstructions,
            instructionOptions: _instructionOptions,
            onModeChanged: (value) =>
                ref.read(fulfilmentModeProvider.notifier).state = value,
            onAddressTap: () => AddressSelectionSheet.show(context),
            onInstructionsChanged: (value) =>
                setState(() => _deliveryInstructions = value),
            onScheduleChanged: (value) =>
                ref.read(scheduledSlotProvider.notifier).state = value,
          ),
          const SizedBox(height: AppSpacing.xxl),
          OrderItemsSection(
            items: items,
            restaurantName: owner.name,
            onEditCart: () => context.push('/cart'),
          ),
          const SizedBox(height: AppSpacing.xxl),
          PromoSection(
            controller: _promoController,
            state: promo,
            onApply: () async {
              await ref
                  .read(promoProvider.notifier)
                  .apply(_promoController.text, subtotal: subtotal);
            },
            onRemove: () {
              _promoController.clear();
              ref.read(promoProvider.notifier).clear();
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          TipSection(
            currency: subtotal.currency,
            selectedIndex: _customTip != null ? -1 : _tipIndex,
            customTip: _customTip,
            onPresetSelected: (index) => setState(() {
              _tipIndex = index;
              _customTip = null;
            }),
            onCustomTip: _askForCustomTip,
          ),
          const SizedBox(height: AppSpacing.xxl),
          const Text('Payment', style: AppTextStyles.h2),
          const SizedBox(height: AppSpacing.sm),
          PaymentMethodPicker(
            selected: _method,
            onSelected: (value) => setState(() {
              _method = value;
              _phoneError = null;
            }),
          ),
          if (_method.requiresOnlinePayment) ...[
            const SizedBox(height: AppSpacing.sm),
            MobileMoneyPhoneField(
              controller: _phoneController,
              method: _method,
              errorText: _phoneError,
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _currencyPicker(quote),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            CheckoutNotice(
              tone: ZvTone.info,
              icon: Icons.payments_outlined,
              title: 'Pay the driver on arrival',
              message:
                  'Have ${quote.total.format()} ready. Drivers may not carry '
                  'change for large notes.',
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          PriceBreakdownSection(quote: quote, promo: promo),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Prices are quoted in US dollars. '
            'Zvingo charges exactly the total above — no fees are added later.',
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _currencyPicker(OrderQuote quote) {
    final ratesAsync = ref.watch(exchangeRatesProvider);
    return ratesAsync.maybeWhen(
      data: (rates) => SettlementCurrencyPicker(
        selected: _settlementCurrency,
        rates: rates,
        usdAmount: quote.total,
        onSelected: (code) => setState(() => _settlementCurrency = code),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }

  String _primaryLabel(OrderQuote quote, DateTime? scheduledAt) {
    final amount = quote.total.format();
    if (scheduledAt != null) return 'Schedule order · $amount';
    if (!_method.requiresOnlinePayment) return 'Place order · $amount';
    return 'Pay $amount with ${_method.label}';
  }

  /// The single source of "why can't I tap the button".
  String? _blockingReason({
    required Restaurant? restaurant,
    required DeliveryLocation? location,
    required FulfilmentMode mode,
    required OrderQuote quote,
    required DateTime? scheduledAt,
  }) {
    if (ref.read(orderPlacementProvider).isPlaced) {
      return null;
    }
    if (restaurant != null && !restaurant.isOpen) {
      if (!restaurant.availability.acceptsScheduled) {
        return '${restaurant.name} is ${restaurant.availability.label.toLowerCase()}, '
            'so this order cannot be placed yet.';
      }
      if (scheduledAt == null) {
        return '${restaurant.name} is ${restaurant.availability.label.toLowerCase()}. '
            'Pick a time under "When" to pre-order.';
      }
    }
    if (location == null) {
      return mode == FulfilmentMode.pickup
          ? 'We still need your location to confirm the pickup — tap "Change" above.'
          : 'Add a delivery address so we know where to bring your order.';
    }
    final minimum = restaurant?.minimumOrder;
    if (minimum != null && quote.subtotal < minimum) {
      final shortfall = minimum - quote.subtotal;
      return 'Add ${shortfall.format()} more to reach this restaurant\'s '
          '${minimum.format()} minimum.';
    }
    if (_method.requiresOnlinePayment) {
      final error = Payment.validatePhone(_phoneController.text);
      if (error != null) {
        return _submitAttempted
            ? error
            : 'Enter the ${_method.label} number to pay from.';
      }
    }
    if (!quote.reconciles) {
      return 'We could not confirm the total. Reload the cart and try again.';
    }
    return null;
  }

  // ── Actions ────────────────────────────────────────────────────

  Future<void> _askForCustomTip(String currency) async {
    final controller = TextEditingController(
      text: _customTip?.toEditableString() ?? '',
    );
    final result = await showModalBottomSheet<Money>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => CustomTipSheet(
        controller: controller,
        currency: currency,
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => _customTip = result);
  }

  Future<void> _placeOrder(
    OrderQuote quote,
    DeliveryLocation? location,
    Restaurant? restaurant,
  ) async {
    setState(() => _submitAttempted = true);
    if (location == null) return;

    if (_method.requiresOnlinePayment) {
      final error = Payment.validatePhone(_phoneController.text);
      if (error != null) {
        setState(() => _phoneError = error);
        return;
      }
    }

    final promo = ref.read(promoProvider);
    final scheduledAt = ref.read(scheduledSlotProvider);
    final placement = ref.read(orderPlacementProvider.notifier);

    final result = await placement.place(
      dropoffLat: location.lat,
      dropoffLng: location.lng,
      quote: quote,
      deliveryInstructions: quote.isPickup ? null : _deliveryInstructions,
      promoCode: promo.isApplied ? promo.code : null,
      scheduledAt: scheduledAt,
    );
    if (result == null || !mounted) return;

    _placedThisSession = true;
    await _rememberAddress(location);

    // The server is the authority on the discount it actually applied.
    final settled = quote.copyWith(
      discount: result.discount.currency == quote.currency
          ? result.discount
          : quote.discount,
    );
    setState(() => _placedQuote = settled);

    if (_method.requiresOnlinePayment) {
      final started = await ref.read(paymentProvider.notifier).initiatePayment(
            orderId: result.primaryOrderId,
            method: _method,
            phone: _phoneController.text,
            currency: _settlementCurrency,
            amount: _amountToCharge(settled),
          );
      if (!mounted) return;
      // Polling continues; the `ref.listen` in build celebrates when it
      // settles, and the failure panel in the footer explains it if it does not.
      if (!started) return;
      return;
    }

    _celebrated = true;
    await _celebrate(result.primaryOrderId, settled, restaurant, location);
  }

  Money _amountToCharge(OrderQuote quote) {
    if (_settlementCurrency == kDefaultCurrency) return quote.total;
    final rates = ref.read(exchangeRatesProvider).valueOrNull;
    final rate = rates?[_settlementCurrency];
    if (rate == null) return quote.total;
    return quote.total.convertTo(_settlementCurrency, rate);
  }

  Future<void> _rememberAddress(DeliveryLocation location) async {
    final saved = ref.read(savedAddressesProvider);
    final exists = saved.any((a) =>
        (a.lat - location.lat).abs() < 0.001 &&
        (a.lng - location.lng).abs() < 0.001);
    if (exists) return;
    await ref.read(savedAddressesProvider.notifier).addAddress(SavedAddress(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          label: 'Recent',
          address: location.displayName,
          lat: location.lat,
          lng: location.lng,
          isDefault: false,
        ));
  }

  Future<void> _celebrate(
    String orderId,
    OrderQuote quote,
    Restaurant? restaurant,
    DeliveryLocation? location,
  ) async {
    if (!mounted) return;
    final scheduledAt = ref.read(scheduledSlotProvider);
    final etaText = scheduledAt != null
        ? _formatSlot(scheduledAt)
        : (restaurant?.deliveryTime ?? '30–45 min');

    // Drive the shell's sticky order banner (§5.4) so the order stays reachable
    // from every tab.
    ref.read(shellOrderBannerProvider.notifier).show(ZvOrderBannerData(
          orderId: orderId,
          statusLabel: quote.isPickup
              ? 'Your order is being prepared'
              : 'Your order is on its way',
          etaText: etaText,
          progress: 0.1,
        ));

    await showOrderPlacedSheet(
      context,
      orderId: orderId,
      quote: quote,
      method: _method,
      isScheduled: scheduledAt != null,
      etaText: etaText,
      addressLabel: quote.isPickup
          ? (restaurant?.address.isNotEmpty ?? false
              ? restaurant!.address
              : restaurant?.name)
          : location?.displayName,
    );

    // Reset the funnel so the next order starts clean. The basket is cleared
    // here rather than at submission, so it survives a failed payment.
    ref.read(cartProvider.notifier).clear();
    ref.read(orderPlacementProvider.notifier).reset();
    ref.read(promoProvider.notifier).clear();
    ref.read(scheduledSlotProvider.notifier).state = null;
    ref.read(paymentProvider.notifier).reset();
  }

  void _retryPayment() {
    final result = ref.read(orderPlacementProvider).result;
    final quote = _placedQuote;
    if (result == null || quote == null) {
      ref.read(orderPlacementProvider.notifier).dismissError();
      return;
    }
    final error = Payment.validatePhone(_phoneController.text);
    if (error != null) {
      setState(() => _phoneError = error);
      return;
    }
    ref.read(paymentProvider.notifier).initiatePayment(
          orderId: result.primaryOrderId,
          method: _method,
          phone: _phoneController.text,
          currency: _settlementCurrency,
          amount: _amountToCharge(quote),
        );
  }

  void _openPaymentScreen() {
    final result = ref.read(orderPlacementProvider).result;
    final quote = _placedQuote;
    if (result == null || quote == null) return;
    ref.read(paymentProvider.notifier).reset();
    // The payment screen quotes in USD and converts for display, so hand it the
    // USD total rather than whatever settlement currency was chosen here.
    context.push(
      '/payment/${result.primaryOrderId}?amount=${quote.total.major}',
    );
  }

  static String _formatSlot(DateTime slot) {
    final local = slot.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final today = DateTime.now();
    final isToday = local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    return isToday
        ? 'Today at $hh:$mm'
        : '${local.day}/${local.month} at $hh:$mm';
  }
}

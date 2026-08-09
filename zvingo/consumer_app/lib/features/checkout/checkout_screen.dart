import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/address/saved_address.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/payment/payment_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:consumer_app/features/order/active_order_provider.dart';
import 'package:go_router/go_router.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final String? restaurantId; // null = checkout all

  const CheckoutScreen({super.key, this.restaurantId});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _deliveryInstructions = 'Leave at door';
  int _selectedTipIndex = 1; // default $2.00
  double _customTip = 0;
  bool _isCustomTip = false;
  PaymentMethodType _selectedPayment = PaymentMethodType.ecocash;
  final _phoneController = TextEditingController();
  bool _isPlacingOrder = false;
  bool _cartExpanded = true;

  final _deliveryOptions = [
    'Leave at door',
    'Hand it to me',
    'Meet outside',
  ];

  final _tipAmounts = [1.75, 2.25, 2.75];

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  double get _selectedTip {
    if (_isCustomTip) return _customTip;
    if (_selectedTipIndex >= 0 && _selectedTipIndex < _tipAmounts.length) {
      return _tipAmounts[_selectedTipIndex];
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final deliveryLoc = ref.watch(deliveryLocationNotifierProvider);
    // Filter items for this checkout
    final items = widget.restaurantId != null
        ? cartItems.where((i) => i.restaurantId == widget.restaurantId).toList()
        : cartItems;

    final restaurantName =
        items.isNotEmpty ? items.first.restaurantName ?? 'Store' : 'Store';
    final subtotal = items.fold(0.0, (sum, item) => sum + item.total);

    // Resolve delivery fee from the restaurant's configured value
    final resolvedRestaurantId =
        widget.restaurantId ?? items.firstOrNull?.restaurantId;
    final restaurantAsync = resolvedRestaurantId != null
        ? ref.watch(restaurantDetailProvider(resolvedRestaurantId))
        : null;
    final deliveryFee = restaurantAsync?.valueOrNull?.deliveryFee ?? 0.0;
    final serviceFee = (subtotal * 0.15).clamp(0.99, 9.99);
    final estimatedTax = subtotal * 0.08;
    final totalBeforeTip = subtotal + deliveryFee + serviceFee + estimatedTax;
    final total = totalBeforeTip + _selectedTip;

    // Listen for payment success
    ref.listen(paymentProvider, (prev, next) {
      if (next.status == 'PAID' && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Payment confirmed!'),
              backgroundColor: AppColors.primary),
        );
        // Navigate to order tracking — find the order ID
        // We stored it during checkout
      }
    });

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text('Checkout',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            Text(restaurantName, style: AppTextStyles.titleMedium),
          ],
        ),
        centerTitle: true,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: items.isEmpty
          ? const Center(child: Text('No items to checkout'))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Address Details ─────────────────────
                  _buildSectionHeader('Address details'),
                  _buildAddressCard(deliveryLoc),
                  _buildDeliveryInstructions(),

                  const Divider(
                      height: 32, thickness: 8, color: AppColors.background),

                  // ── Delivery Time ──────────────────────
                  _buildSectionHeader('Delivery time'),
                  _buildDeliveryTimeOptions(),

                  const Divider(
                      height: 32, thickness: 8, color: AppColors.background),

                  // ── Cart Summary ───────────────────────
                  _buildSectionHeader('Cart summary'),
                  _buildCartSummary(items, restaurantName),

                  const Divider(
                      height: 32, thickness: 8, color: AppColors.background),

                  // ── Save More ─────────────────────────
                  _buildSectionHeader('Save more'),
                  _buildSaveMoreSection(),

                  const Divider(
                      height: 32, thickness: 8, color: AppColors.background),

                  // ── Price Summary ──────────────────────
                  _buildSectionHeader('Price summary'),
                  _buildPriceSummary(
                    subtotal: subtotal,
                    deliveryFee: deliveryFee,
                    serviceFee: serviceFee,
                    estimatedTax: estimatedTax,
                    totalBeforeTip: totalBeforeTip,
                  ),

                  const Divider(
                      height: 32, thickness: 8, color: AppColors.background),

                  // ── Tip ────────────────────────────────
                  _buildSectionHeader('Shopper Tip \u24D8'),
                  _buildTipSection(),

                  const Divider(
                      height: 32, thickness: 8, color: AppColors.background),

                  // ── Payment Method ─────────────────────
                  _buildSectionHeader('Payment'),
                  _buildPaymentSection(),

                  const SizedBox(height: 100),
                ],
              ),
            ),

      // ── Place Order Button ─────────────────────
      bottomNavigationBar: items.isNotEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_isPlacingOrder || deliveryLoc == null)
                        ? null
                        : () => _placeOrder(
                              cartNotifier: cartNotifier,
                              deliveryLoc: deliveryLoc,
                              total: total,
                              deliveryFee: deliveryFee,
                              serviceFee: serviceFee,
                              estimatedTax: estimatedTax,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.textHint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isPlacingOrder
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Place order',
                                  style: AppTextStyles.button
                                      .copyWith(fontSize: 16)),
                              Text(
                                '\$${total.toStringAsFixed(2)}',
                                style:
                                    AppTextStyles.button.copyWith(fontSize: 16),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  // ── Section Header ─────────────────────────────────
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Text(title,
          style:
              AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  // ── Save More Section ─────────────────────────────
  Widget _buildSaveMoreSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Deals and benefits row
            InkWell(
              onTap: () {},
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deals and benefits',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text('None selected',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textHint)),
                        ],
                      ),
                    ),
                    Text('Add code/gift card',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textHint),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Address Card ───────────────────────────────────
  Widget _buildAddressCard(DeliveryLocation? loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Map placeholder
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.primarySurface.withOpacity(0.5),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Grid lines to simulate map
                  CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: _MapGridPainter(),
                  ),
                  // Pin icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // Address row
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: AppColors.textSecondary, size: 22),
              title: Text(
                loc?.displayName ?? 'Set delivery address',
                style: AppTextStyles.bodyMedium
                    .copyWith(fontWeight: FontWeight.w500),
                maxLines: 2,
              ),
              trailing: const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textHint),
              onTap: () => AddressSelectionSheet.show(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delivery Instructions ──────────────────────────
  Widget _buildDeliveryInstructions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          leading: const Icon(Icons.inventory_2_outlined,
              size: 22, color: AppColors.textSecondary),
          title: Text(_deliveryInstructions, style: AppTextStyles.bodyMedium),
          subtitle:
              const Text('Delivery instructions', style: AppTextStyles.bodySmall),
          trailing: const Icon(Icons.chevron_right,
              size: 20, color: AppColors.textHint),
          onTap: () => _showDeliveryInstructionsPicker(),
        ),
      ),
    );
  }

  void _showDeliveryInstructionsPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delivery instructions', style: AppTextStyles.titleLarge),
            const SizedBox(height: 16),
            ..._deliveryOptions.map((option) {
              final selected = _deliveryInstructions == option;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.primary : AppColors.textHint,
                ),
                title: Text(option, style: AppTextStyles.bodyMedium),
                onTap: () {
                  setState(() => _deliveryInstructions = option);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── Delivery Time Options ──────────────────────────
  Widget _buildDeliveryTimeOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            _DeliveryTimeOption(
              title: 'Priority',
              subtitle: 'Direct to you',
              price: '\$3.99',
              isSelected: false,
              onTap: () {},
            ),
            const Divider(height: 1),
            _DeliveryTimeOption(
              title: 'Standard',
              subtitle: '25-40 min',
              price: null,
              isSelected: true,
              onTap: () {},
            ),
            const Divider(height: 1),
            _DeliveryTimeOption(
              title: 'Schedule Ahead',
              subtitle: 'Choose a time',
              price: null,
              isSelected: false,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  // ── Cart Summary ───────────────────────────────────
  Widget _buildCartSummary(List<CartItem> items, String restaurantName) {
    final itemCount = items.fold(0, (int sum, item) => sum + item.quantity);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Header
            InkWell(
              onTap: () => setState(() => _cartExpanded = !_cartExpanded),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$restaurantName \u2022 $itemCount ${itemCount == 1 ? 'item' : 'items'}',
                        style: AppTextStyles.titleSmall,
                      ),
                    ),
                    Icon(
                      _cartExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.textHint,
                    ),
                  ],
                ),
              ),
            ),
            // Items
            if (_cartExpanded) ...[
              const Divider(height: 1),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.quantity}x',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        Expanded(
                          child:
                              Text(item.name, style: AppTextStyles.bodyMedium),
                        ),
                        Text(
                          '\$${item.total.toStringAsFixed(2)}',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ── Price Summary ──────────────────────────────────
  Widget _buildPriceSummary({
    required double subtotal,
    required double deliveryFee,
    required double serviceFee,
    required double estimatedTax,
    required double totalBeforeTip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            _priceRow('Subtotal', subtotal),
            const SizedBox(height: 10),
            _priceRow('Delivery Fee', deliveryFee, hasInfo: true),
            const SizedBox(height: 10),
            _priceRow('Service Fee', serviceFee, hasInfo: true),
            const SizedBox(height: 10),
            _priceRow('Estimated Tax', estimatedTax, hasInfo: true),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total before tip', style: AppTextStyles.titleSmall),
                Text('\$${totalBeforeTip.toStringAsFixed(2)}',
                    style: AppTextStyles.titleSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(String label, double amount, {bool hasInfo = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(label,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
            if (hasInfo) ...[
              const SizedBox(width: 4),
              const Icon(Icons.info_outline,
                  size: 14, color: AppColors.textHint),
            ],
          ],
        ),
        Text('\$${amount.toStringAsFixed(2)}', style: AppTextStyles.bodyMedium),
      ],
    );
  }

  // ── Tip Section ────────────────────────────────────
  Widget _buildTipSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '100% of the tip goes to your shopper.',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ..._tipAmounts.asMap().entries.map((entry) {
                final index = entry.key;
                final amount = entry.value;
                final selected = !_isCustomTip && _selectedTipIndex == index;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: index < _tipAmounts.length - 1 ? 8 : 0),
                    child: _TipChip(
                      label: '\$${amount.toStringAsFixed(2)}',
                      isSelected: selected,
                      onTap: () => setState(() {
                        _selectedTipIndex = index;
                        _isCustomTip = false;
                      }),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 8),
              Expanded(
                child: _TipChip(
                  label: 'Other',
                  isSelected: _isCustomTip,
                  onTap: () => _showCustomTipDialog(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCustomTipDialog() {
    final controller = TextEditingController(
        text: _customTip > 0 ? _customTip.toStringAsFixed(2) : '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom tip'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: '\$ ',
            hintText: '0.00',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text) ?? 0;
              setState(() {
                _customTip = val;
                _isCustomTip = true;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ── Payment Section ────────────────────────────────
  Widget _buildPaymentSection() {
    final isCash = _selectedPayment == PaymentMethodType.cash;
    final isCard = _selectedPayment == PaymentMethodType.card;
    final hidesPhoneInput = isCash || isCard;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Horizontally scrollable payment options (DoorDash style)
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PaymentPill(
                  imagePath: 'assets/images/ecocash.png',
                  label: 'EcoCash',
                  color: const Color(0xFF00A651),
                  isSelected: _selectedPayment == PaymentMethodType.ecocash,
                  onTap: () => setState(
                      () => _selectedPayment = PaymentMethodType.ecocash),
                ),
                const SizedBox(width: 10),
                _PaymentPill(
                  imagePath: 'assets/images/onemoney.png',
                  label: 'OneMoney',
                  color: const Color(0xFFF97316),
                  isSelected: _selectedPayment == PaymentMethodType.onemoney,
                  onTap: () => setState(
                      () => _selectedPayment = PaymentMethodType.onemoney),
                ),
                const SizedBox(width: 10),
                _PaymentPill(
                  imagePath: 'assets/images/innbucks.png',
                  label: 'InnBucks',
                  color: const Color(0xFF1B3A6B),
                  isSelected: _selectedPayment == PaymentMethodType.innbucks,
                  onTap: () => setState(
                      () => _selectedPayment = PaymentMethodType.innbucks),
                ),
                const SizedBox(width: 10),
                _PaymentPill(
                  imagePath: 'assets/images/cash.png',
                  label: 'Cash',
                  color: const Color(0xFF4CAF50),
                  isSelected: isCash,
                  onTap: () =>
                      setState(() => _selectedPayment = PaymentMethodType.cash),
                ),
                const SizedBox(width: 10),
                _PaymentPill(
                  iconData: Icons.credit_card,
                  label: 'Visa / MC',
                  color: const Color(0xFF1A1F71),
                  isSelected: _selectedPayment == PaymentMethodType.card,
                  onTap: () =>
                      setState(() => _selectedPayment = PaymentMethodType.card),
                ),
                const SizedBox(width: 10),
                // "Add payment" pill
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 90,
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add,
                            size: 24, color: AppColors.textSecondary),
                        const SizedBox(height: 4),
                        Text(
                          'Add payment',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Info banner (hidden for mobile money)
          if (hidesPhoneInput) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isCash
                          ? 'Pay your driver in cash when your order arrives.'
                          : 'Card payments coming soon.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Phone number input (hidden for cash and card)
          if (!hidesPhoneInput) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '+263 7X XXX XXXX',
                hintStyle: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textHint),
                prefixIcon: const Icon(Icons.phone,
                    color: AppColors.textHint, size: 20),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Place Order Logic ──────────────────────────────
  Future<void> _placeOrder({
    required Cart cartNotifier,
    required DeliveryLocation deliveryLoc,
    required double total,
    required double deliveryFee,
    required double serviceFee,
    required double estimatedTax,
  }) async {
    final isCash = _selectedPayment == PaymentMethodType.cash;
    final isCard = _selectedPayment == PaymentMethodType.card;
    final phone = _phoneController.text.trim();

    if (isCard) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card payments coming soon')),
      );
      return;
    }

    if (!isCash && phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter your phone number for payment')),
      );
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      // 1. Create the order with all fee details
      final orderIds = await cartNotifier.checkout(
        deliveryLoc.lat,
        deliveryLoc.lng,
        restaurantId: widget.restaurantId,
        deliveryInstructions: _deliveryInstructions,
        tipAmount: _selectedTip,
        deliveryFee: deliveryFee,
        serviceFee: serviceFee,
        taxAmount: estimatedTax,
      );

      if (orderIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create order')),
          );
          setState(() => _isPlacingOrder = false);
        }
        return;
      }

      // Auto-save the delivery address if it's not already stored.
      final savedAddresses = ref.read(savedAddressesProvider);
      final alreadySaved = savedAddresses.any(
        (a) =>
            (a.lat - deliveryLoc.lat).abs() < 0.001 &&
            (a.lng - deliveryLoc.lng).abs() < 0.001,
      );
      if (!alreadySaved) {
        await ref.read(savedAddressesProvider.notifier).addAddress(SavedAddress(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              label: 'Recent',
              address: deliveryLoc.displayName,
              lat: deliveryLoc.lat,
              lng: deliveryLoc.lng,
              isDefault: false,
            ));
      }

      final orderId = orderIds.first;

      if (isCash) {
        // 2a. Cash on delivery — no payment initiation needed.
        //     Activate the order and go home; driver will collect cash.
        if (mounted) {
          ref.read(activeOrderProvider.notifier).state = orderId;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Order placed! Pay your driver in cash on delivery.'),
              backgroundColor: AppColors.primary,
            ),
          );
          context.go('/home');
        }
      } else {
        // 2b. Mobile money — initiate payment and poll for confirmation.
        final success =
            await ref.read(paymentProvider.notifier).initiatePayment(
                  orderId: orderId,
                  method: _selectedPayment,
                  phone: phone,
                );

        if (mounted) {
          if (success) {
            ref.read(activeOrderProvider.notifier).state = orderId;
            context.go('/home');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Payment initiation failed. Please try again.')),
            );
          }
        }
      }

      if (mounted) setState(() => _isPlacingOrder = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isPlacingOrder = false);
      }
    }
  }
}

// ── Helper Widgets ───────────────────────────────────

class _DeliveryTimeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? price;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeliveryTimeOption({
    required this.title,
    required this.subtitle,
    this.price,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            if (price != null) ...[
              Text(price!, style: AppTextStyles.bodyMedium),
              const SizedBox(width: 12),
            ],
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? AppColors.primary : AppColors.textHint,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TipChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.textPrimary : AppColors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.textPrimary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentPill extends StatelessWidget {
  final String? imagePath;
  final IconData? iconData;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentPill({
    this.imagePath,
    this.iconData,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  }) : assert(imagePath != null || iconData != null,
            'Either imagePath or iconData must be provided');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (imagePath != null)
              Image.asset(
                imagePath!,
                height: 28,
                width: 56,
                fit: BoxFit.contain,
              )
            else if (iconData != null)
              Icon(
                iconData,
                size: 28,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isSelected ? color : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withOpacity(0.1)
      ..strokeWidth = 0.5;
    // Draw grid
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

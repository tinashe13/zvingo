/// The cart — review, adjust, and leave for checkout.
///
/// Everything here is reversible: a quantity change is optimistic and instant,
/// a removal returns an undo snackbar that puts the line back at the same
/// index, and clearing the cart asks first and is also undoable. The only
/// irreversible step in the funnel is on the next screen.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/checkout/order_placement_provider.dart';
import 'package:consumer_app/features/checkout/order_quote.dart';
import 'package:consumer_app/features/restaurant/menu/menu_item_sheet.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final owner = ref.watch(cartOwnerProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final units = ref.watch(cartUnitCountProvider);
    final deliveryLocation = ref.watch(deliveryLocationNotifierProvider);
    final mode = ref.watch(fulfilmentModeProvider);

    if (items.isEmpty) {
      return ZvScreen(
        title: 'Your cart',
        fallbackRoute: '/home',
        child: ZvEmptyState(
          icon: Icons.shopping_bag_outlined,
          title: 'Your cart is empty',
          message: 'Pick a restaurant and add something you fancy — '
              'it will show up here.',
          actionLabel: 'Browse restaurants',
          onAction: () => context.go('/home'),
        ),
      );
    }

    final restaurantAsync = owner.id == null
        ? null
        : ref.watch(restaurantDetailProvider(owner.id!));
    final restaurant = restaurantAsync?.valueOrNull;

    final minimumOrder = restaurant?.minimumOrder;
    final shortfall = minimumOrder == null || subtotal >= minimumOrder
        ? null
        : minimumOrder - subtotal;

    final quote = OrderQuote.forCart(
      subtotal: subtotal,
      mode: mode,
      restaurantDeliveryFee: restaurant?.deliveryFeeMoney,
      restaurantLat: restaurant?.latitude,
      restaurantLng: restaurant?.longitude,
      dropoffLat: deliveryLocation?.lat,
      dropoffLng: deliveryLocation?.lng,
    );

    final closed = restaurant != null && !restaurant.isOpen;
    final blockedReason = closed
        ? '${restaurant.name} is ${restaurant.availability.label.toLowerCase()}. '
            'Your cart is saved — come back when it reopens.'
        : shortfall != null
            ? 'Add ${shortfall.format()} more to reach '
                '${minimumOrder!.format()}, the minimum for this restaurant.'
            : null;

    return ZvScreen(
      title: 'Your cart',
      subtitle: owner.name,
      fallbackRoute: '/home',
      actions: [
        ZvIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Empty cart',
          onPressed: () => _confirmClear(context, ref, items),
        ),
      ],
      footer: ZvStickyFooter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Subtotal',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textSecondary)),
                const Spacer(),
                ZvAnimatedCount.money(
                  value: subtotal.major,
                  currency: subtotal.symbol,
                  style: AppTextStyles.moneyLarge,
                  semanticLabel: 'Cart subtotal',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              mode == FulfilmentMode.pickup
                  ? 'Fees are confirmed at checkout. Pickup has no delivery fee.'
                  : 'Delivery and service fees are shown in full at checkout.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ZvButton.primary(
              label: 'Go to checkout',
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: blockedReason != null
                  ? null
                  : () => context.push('/checkout'),
              disabledReason: blockedReason,
            ),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          _FulfilmentToggle(
            mode: mode,
            onChanged: (value) =>
                ref.read(fulfilmentModeProvider.notifier).state = value,
          ),
          if (mode == FulfilmentMode.delivery) ...[
            const SizedBox(height: AppSpacing.sm),
            _DeliveryAddressCard(
              location: deliveryLocation,
              onTap: () => AddressSelectionSheet.show(context),
            ),
          ],
          if (closed) ...[
            const SizedBox(height: AppSpacing.sm),
            _CartNotice(
              tone: ZvTone.warning,
              icon: Icons.schedule_rounded,
              message: blockedReason!,
            ),
          ] else if (shortfall != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _CartNotice(
              tone: ZvTone.info,
              icon: Icons.add_shopping_cart_rounded,
              message: blockedReason!,
              actionLabel: 'Add more items',
              onAction: owner.id == null
                  ? null
                  : () => context.push('/restaurant/${owner.id}'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$units item${units == 1 ? '' : 's'}',
                  style: AppTextStyles.h3,
                ),
              ),
              if (owner.id != null)
                ZvButton.tertiary(
                  label: 'Add more',
                  icon: Icons.add_rounded,
                  onPressed: () => context.push('/restaurant/${owner.id}'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ZvStaggeredList(
            children: [
              for (final item in items)
                _CartLineTile(
                  key: ValueKey(item.lineId),
                  item: item,
                  restaurant: restaurant,
                  onQuantityChanged: (value) => ref
                      .read(cartProvider.notifier)
                      .setQuantity(item.lineId, value),
                  onRemove: () => _removeWithUndo(context, ref, item),
                  onEdit: restaurant == null
                      ? null
                      : () => _edit(context, ref, restaurant, item),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _PreviewBreakdown(quote: quote, mode: mode),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────

  void _removeWithUndo(BuildContext context, WidgetRef ref, CartItem item) {
    final snapshot = ref.read(cartProvider.notifier).removeLine(item.lineId);
    if (snapshot == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${item.name} removed'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                ref.read(cartProvider.notifier).restoreLine(snapshot),
          ),
        ),
      );
  }

  Future<void> _confirmClear(
    BuildContext context,
    WidgetRef ref,
    List<CartItem> items,
  ) async {
    final snapshot = List<CartItem>.from(items);
    final confirmed = await showZvConfirmSheet(
      context,
      title: 'Empty your cart?',
      consequence: 'All ${items.length} '
          'item${items.length == 1 ? '' : 's'} will be removed. '
          'You can undo this straight afterwards.',
      confirmLabel: 'Empty cart',
      cancelLabel: 'Keep my cart',
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed != true) return;
    ref.read(cartProvider.notifier).clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Cart emptied'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => ref.read(cartProvider.notifier).restoreAll(snapshot),
        ),
      ));
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Restaurant restaurant,
    CartItem line,
  ) async {
    MenuItem? menuItem;
    for (final candidate in restaurant.menu) {
      if (candidate.id == line.itemId) {
        menuItem = candidate;
        break;
      }
    }
    if (menuItem == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${line.name} is no longer on ${restaurant.name}\'s menu. '
            'Remove it to carry on.',
          ),
        ));
      return;
    }
    final updated = await showMenuItemSheet(
      context,
      item: menuItem,
      restaurant: restaurant,
      editing: line,
    );
    if (updated == null) return;
    ref.read(cartProvider.notifier).replaceLine(line.lineId, updated);
  }
}

// ── Pieces ───────────────────────────────────────────────────────

class _FulfilmentToggle extends StatelessWidget {
  const _FulfilmentToggle({required this.mode, required this.onChanged});

  final FulfilmentMode mode;
  final ValueChanged<FulfilmentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.fullAll,
      ),
      child: Row(
        children: [
          _segment(context, FulfilmentMode.delivery, 'Delivery',
              Icons.delivery_dining_outlined),
          _segment(context, FulfilmentMode.pickup, 'Pickup',
              Icons.storefront_outlined),
        ],
      ),
    );
  }

  Widget _segment(
      BuildContext context, FulfilmentMode value, String label, IconData icon) {
    final selected = mode == value;
    return Expanded(
      child: ZvTapScale(
        onTap: () => onChanged(value),
        semanticLabel: label,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.fast),
          curve: context.motionCurve(AppMotion.standard),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.actionDefault : Colors.transparent,
            borderRadius: AppRadius.fullAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? AppColors.textOnDark
                      : AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTextStyles.button.copyWith(
                  color:
                      selected ? AppColors.textOnDark : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryAddressCard extends StatelessWidget {
  const _DeliveryAddressCard({required this.location, required this.onTap});

  final DeliveryLocation? location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasAddress = location != null;
    return ZvCard(
      onTap: onTap,
      color: hasAddress ? AppColors.surface : AppColors.warningSurface,
      borderColor: hasAddress ? AppColors.border : AppColors.warning,
      child: Row(
        children: [
          Icon(
            hasAddress
                ? Icons.location_on_outlined
                : Icons.wrong_location_outlined,
            size: 20,
            color: hasAddress ? AppColors.textSecondary : AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasAddress ? 'Delivering to' : 'No delivery address yet',
                  style: AppTextStyles.caption.copyWith(
                    color: hasAddress
                        ? AppColors.textSecondary
                        : AppColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasAddress
                      ? location!.displayName
                      : 'Set one so we know where to bring your order',
                  style: AppTextStyles.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(hasAddress ? 'Change' : 'Set',
              style: AppTextStyles.button
                  .copyWith(color: AppColors.actionDefault)),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    super.key,
    required this.item,
    required this.restaurant,
    required this.onQuantityChanged,
    required this.onRemove,
    this.onEdit,
  });

  final CartItem item;
  final Restaurant? restaurant;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final soldOut = restaurant != null &&
        !restaurant!.menu.any((m) => m.id == item.itemId && m.isAvailable);

    return ZvCard(
      onTap: onEdit,
      semanticLabel: '${item.name}, quantity ${item.quantity}, '
          '${item.lineTotal.format()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.smAll,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: ZvNetworkImage(
                    url: item.imageUrl,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                    fallbackIcon: Icons.restaurant_menu_rounded,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: AppTextStyles.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (item.choices.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.choicesSummary,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((item.specialInstructions ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.edit_note_rounded,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.specialInstructions!,
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      item.quantity > 1
                          ? '${item.unitPrice.format()} each'
                          : item.unitPrice.format(),
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ZvAnimatedCount.money(
                value: item.lineTotal.major,
                currency: item.lineTotal.symbol,
                style: AppTextStyles.money,
                semanticLabel: 'Line total for ${item.name}',
              ),
            ],
          ),
          if (soldOut) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(Icons.remove_shopping_cart_outlined,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    'Sold out since you added it — remove it to check out.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              ZvStepper(
                value: item.quantity,
                min: 1,
                max: 50,
                compact: true,
                deleteAtMin: true,
                onDelete: onRemove,
                semanticLabel: 'Quantity of ${item.name}',
                onChanged: onQuantityChanged,
              ),
              const Spacer(),
              if (onEdit != null)
                ZvButton.tertiary(
                  label: item.isCustomised ? 'Edit choices' : 'Add a note',
                  icon: Icons.tune_rounded,
                  onPressed: onEdit,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartNotice extends StatelessWidget {
  const _CartNotice({
    required this.tone,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final ZvTone tone;
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: AppTextStyles.caption),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  ZvButton.tertiary(label: actionLabel!, onPressed: onAction),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A read-only preview of the fee breakdown so the cart is not a black box.
/// Checkout owns the authoritative version.
class _PreviewBreakdown extends StatelessWidget {
  const _PreviewBreakdown({required this.quote, required this.mode});

  final OrderQuote quote;
  final FulfilmentMode mode;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      color: AppColors.background,
      child: Column(
        children: [
          _row('Subtotal', quote.subtotal),
          const SizedBox(height: AppSpacing.xs),
          _row(
            mode == FulfilmentMode.pickup
                ? 'Delivery (pickup)'
                : 'Delivery fee',
            quote.deliveryFee,
          ),
          const SizedBox(height: AppSpacing.xs),
          _row('Service fee', quote.serviceFee),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Text('Estimated total', style: AppTextStyles.bodyStrong),
              const Spacer(),
              Text(quote.totalBeforeTip.format(),
                  style: AppTextStyles.bodyStrong),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Before any tip or promo code. Confirmed on the next screen.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, Money amount) {
    return Row(
      children: [
        Text(label,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
        const Spacer(),
        Text(amount.isZero ? 'Free' : amount.format(),
            style: AppTextStyles.money),
      ],
    );
  }
}

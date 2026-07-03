import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We watch the notifier to access the grouped items getter
    // Note: In Riverpod 2.x, watching the provider gives the state (List<CartItem>)
    // To access the getter dealing with logic, we use ref.read on notifier or ref.watch(cartProvider) then helper
    // Actually, we can add the getter to the Cart class (List) extension or keep logic in notifier
    // But since I added `get groupedItems` to the `Cart` class (which extends _$Cart -> Notifier), it's on the notifier.
    // So we need ref.watch(cartProvider.notifier).groupedItems -- BUT watching notifier doesn't trigger rebuilds on state change alone usually.
    // Better approach: ref.watch(cartProvider) gives us the list. We can compute groups here or in a provider.
    // I added `groupedItems` on the Notifier class `Cart`. To access it reactively, keeping state as source of truth.
    
    final cartItems = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final groupedItems = cartNotifier.groupedItems; // This getter uses `state`, but accessing it via read(notifier) might not be reactive if we don't watch state.
    // However, `cartItems` (state) is watched, so this build method re-runs when items change. 
    // So `cartNotifier.groupedItems` will be re-evaluated with the new state.
    
    final total = ref.watch(cartTotalProvider);
    final deliveryLoc = ref.watch(deliveryLocationNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Your Carts', style: AppTextStyles.titleLarge),
        centerTitle: true,
      ),
      body: cartItems.isEmpty
          ? _emptyState()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Delivery address bar
                _DeliveryAddressBar(
                  deliveryLoc: deliveryLoc,
                  onTap: () => AddressSelectionSheet.show(context),
                ),
                const SizedBox(height: 16),
                ...groupedItems.entries.map((entry) {
                  final restaurantId = entry.key;
                  final items = entry.value;
                  // Try to find restaurant name from first item
                  final restaurantName = items.isNotEmpty ? items.first.restaurantName : 'Unknown Store';
                  final restaurantImage = items.isNotEmpty ? items.first.restaurantImage : null;
                  final storeTotal = items.fold(0.0, (sum, item) => sum + item.total);

                  return _StoreCartSection(
                    restaurantName: restaurantName ?? 'Unknown Store',
                    restaurantImage: restaurantImage,
                    items: items,
                    subtotal: storeTotal,
                    onCheckout: () {
                      context.push('/checkout?restaurantId=$restaurantId');
                    },
                    ref: ref,
                  );
                }),
                
                const SizedBox(height: 100), // Space for bottom bar
              ],
            ),

      // Global Checkout button if multiple stores
      bottomNavigationBar: (groupedItems.keys.length > 1)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      context.push('/checkout');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.textPrimary, // Dark button for "Checkout All"
                    ),
                    child: Text(
                      'Checkout All — \$${(total * 1.05).toStringAsFixed(2)}',
                      style: AppTextStyles.button,
                    ),
                  ),
                ),
              ),
            )
          : null, // If 1 store, the section button handles it (or we can keep bottom bar)
          // Actually, standard pattern is bottom bar for the "Current" context.
          // But with multi-cart, user might want to checkout just one.
          // Strategy: Detailed per-store section with button.
          // "Checkout All" is an aggregation.
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset(
            'assets/animations/empty_cart.json',
            width: 180,
            height: 180,
            repeat: true,
          ),
          const SizedBox(height: 16),
          Text('Your cart is empty', style: AppTextStyles.titleMedium),
          const SizedBox(height: 6),
          Text('Add items from a restaurant to get started',
              style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

class _StoreCartSection extends StatelessWidget {
  final String restaurantName;
  final String? restaurantImage;
  final List<CartItem> items;
  final double subtotal;
  final VoidCallback onCheckout;
  final WidgetRef ref;

  const _StoreCartSection({
    required this.restaurantName,
    this.restaurantImage,
    required this.items,
    required this.subtotal,
    required this.onCheckout,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                restaurantImage != null && restaurantImage!.isNotEmpty
                  ? Container(
                      width: 24, height: 24,
                      decoration: const BoxDecoration(shape: BoxShape.circle),
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: restaurantImage!,
                          fit: BoxFit.cover,
                          placeholder: (_,__) => const Icon(Icons.store, color: AppColors.primary, size: 16),
                          errorWidget: (_,__,___) => const Icon(Icons.store, color: AppColors.primary, size: 16),
                        ),
                      ),
                    )
                  : const Icon(Icons.store, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(restaurantName, style: AppTextStyles.titleMedium),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Items
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _CartItemTile(
                item: item,
                onRemove: () => ref.read(cartProvider.notifier).removeItem(item.id),
                onIncrement: () => ref.read(cartProvider.notifier).addItem(item.id, item.name, item.price),
                onDecrement: () => ref.read(cartProvider.notifier).decrementItem(item.id),
              );
            },
          ),
          
          const Divider(height: 1),
          
          // Footer
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Text('Subtotal', style: AppTextStyles.bodyMedium),
                     Text('\$${subtotal.toStringAsFixed(2)}', style: AppTextStyles.titleSmall),
                   ],
                 ),
                 const SizedBox(height: 16),
                 SizedBox(
                   width: double.infinity,
                   child: ElevatedButton(
                     onPressed: onCheckout,
                     style: ElevatedButton.styleFrom(
                       backgroundColor: AppColors.primary,
                       foregroundColor: Colors.white,
                     ),
                     child: Text('Checkout Store'),
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

class _DeliveryAddressBar extends StatelessWidget {
  final DeliveryLocation? deliveryLoc;
  final VoidCallback onTap;

  const _DeliveryAddressBar({required this.deliveryLoc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasAddress = deliveryLoc != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasAddress ? AppColors.primarySurface : AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasAddress ? AppColors.primary.withOpacity(0.3) : AppColors.error.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasAddress ? Icons.location_on : Icons.location_off_outlined,
              color: hasAddress ? AppColors.primary : AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAddress ? 'Delivering to' : 'No delivery address set',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: hasAddress ? AppColors.textSecondary : AppColors.error,
                      fontSize: 11,
                    ),
                  ),
                  if (hasAddress)
                    Text(
                      deliveryLoc!.displayName,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              hasAddress ? 'Change' : 'Set Address',
              style: AppTextStyles.bodySmall.copyWith(
                color: hasAddress ? AppColors.primary : AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: hasAddress ? AppColors.primary : AppColors.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onRemove;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _CartItemTile({
    required this.item,
    required this.onRemove,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                       imageUrl: item.imageUrl!,
                       fit: BoxFit.cover,
                       placeholder: (_, __) => const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.fastfood, color: AppColors.primary, size: 20)),
                       errorWidget: (_, __, ___) => const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.fastfood, color: AppColors.primary, size: 20)),
                    ),
                  )
                : const Icon(Icons.fastfood, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '\$${item.total.toStringAsFixed(2)}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),

          // Qty stepper + remove button
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey),
                onPressed: onDecrement,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.quantity}', style: AppTextStyles.bodyMedium),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.primary),
                onPressed: onIncrement,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one place the "your cart is from another restaurant" question is asked.
///
/// A Zvingo cart holds one restaurant at a time. That is a deliberate product
/// decision, not a limitation of the cart: `POST /payment/initiate` is scoped to
/// a single `order_id`, so a basket spanning two restaurants would send the
/// customer two separate EcoCash prompts for one checkout. Rather than ship
/// that, the app asks — and the old basket is restorable from the snackbar, so
/// a mis-tap never costs the customer their order.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add [line] to the cart, asking first when it belongs to another restaurant.
///
/// Returns true when the item ended up in the cart.
Future<bool> addToCartWithConflictCheck(
  BuildContext context,
  WidgetRef ref,
  CartItem line,
) async {
  final cart = ref.read(cartProvider.notifier);
  final result = cart.addLine(line);
  if (result.added) return true;

  final previous = List<CartItem>.from(ref.read(cartProvider));
  final previousName = result.existingRestaurantName ?? 'another restaurant';
  final newName = line.restaurantName ?? 'this restaurant';
  final itemWord = previous.length == 1 ? 'item' : 'items';

  if (!context.mounted) return false;
  final confirmed = await showZvConfirmSheet(
    context,
    title: 'Start a new cart?',
    consequence:
        'Your cart has ${previous.length} $itemWord from $previousName. '
        'Zvingo delivers one restaurant per order, so adding '
        '"${line.name}" from $newName will empty it. '
        'You can undo this straight afterwards.',
    confirmLabel: 'Start new cart',
    cancelLabel: 'Keep my cart',
    destructive: true,
    icon: Icons.shopping_bag_outlined,
  );

  if (confirmed != true) return false;

  cart.startNewCartWith(line);

  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('New cart started with ${line.name}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => cart.restoreAll(previous),
          ),
        ),
      );
  }
  return true;
}

/// Snackbar shown when something is added, with a shortcut to the cart.
void showAddedToCartSnackBar(
  BuildContext context, {
  required String itemName,
  required int quantity,
  required VoidCallback onViewCart,
}) {
  final label = quantity > 1 ? '$itemName ×$quantity' : itemName;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$label added to your cart'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(label: 'View cart', onPressed: onViewCart),
      ),
    );
}

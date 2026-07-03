import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MenuScreen extends ConsumerStatefulWidget {
  final String restaurantId;
  const MenuScreen({super.key, required this.restaurantId});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String _selectedCategory = 'All';

  String _formatCount(int? count) {
    if (count == null) return '';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k+';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final restaurantAsync = ref.watch(restaurantDetailProvider(widget.restaurantId));
    final cartItems = ref.watch(cartProvider);
    final cartTotal = ref.watch(cartTotalProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: restaurantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (restaurant) {
          final categories = ['All', ...restaurant.menu.map((e) => e.category).toSet().toList()];
          if (_selectedCategory == 'All' && categories.length > 1 && !categories.contains(_selectedCategory)) {
             _selectedCategory = categories[0];
          }

          final filteredItems = _selectedCategory == 'All'
              ? restaurant.menu
              : restaurant.menu.where((i) => i.category == _selectedCategory).toList();

          return CustomScrollView(
            slivers: [
              // ── Hero Image / App Bar ──────────────────────
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: AppColors.white,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                      onPressed: () => context.pop(),
                    ),
                  ),
                ),
                actions: [
                  // Favourite button
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Builder(
                        builder: (context) {
                          final isFav = ref.watch(favouritesProvider)
                              .contains(widget.restaurantId);
                          return IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? AppColors.error : AppColors.textPrimary,
                            ),
                            onPressed: () => ref
                                .read(favouritesProvider.notifier)
                                .toggle(widget.restaurantId),
                          );
                        },
                      ),
                    ),
                  ),
                  // Share button
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.ios_share, color: AppColors.textPrimary, size: 20),
                        onPressed: () {},
                      ),
                    ),
                  ),
                  // More button
                  Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary, size: 20),
                        onPressed: () {},
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      restaurant.bannerUrl.isNotEmpty || restaurant.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: restaurant.bannerUrl.isNotEmpty ? restaurant.bannerUrl : restaurant.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(color: AppColors.primarySurface),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.primarySurface,
                                child: const Icon(Icons.restaurant, size: 64, color: AppColors.textHint),
                              ),
                            )
                          : Container(
                              color: AppColors.primarySurface,
                              child: const Center(
                                child: Icon(Icons.restaurant, size: 64, color: AppColors.textHint),
                              ),
                            ),
                      // Gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Restaurant Info (DoorDash style) ──────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo + Name row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Restaurant logo
                          Container(
                            width: 60,
                            height: 60,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.white,
                              border: Border.all(color: Colors.grey.shade200, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: restaurant.imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: restaurant.imageUrl,
                                      fit: BoxFit.contain,
                                      placeholder: (context, url) => Container(color: AppColors.primarySurface),
                                    )
                                  : const Icon(Icons.restaurant, size: 28, color: AppColors.primary),
                            ),
                          ),
                          // Name + subtitle
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(restaurant.name, style: AppTextStyles.headlineMedium),
                                const SizedBox(height: 2),
                                // DoorDash-style subtitle: "Zvingo+ · Category · X.X mi"
                                Text.rich(
                                  TextSpan(
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                    children: [
                                      const TextSpan(text: 'Zvingo+ ', style: TextStyle(fontWeight: FontWeight.w600)),
                                      const TextSpan(text: ' \u00B7 '),
                                      TextSpan(text: restaurant.category),
                                      if (restaurant.distanceMi != null) ...[
                                        const TextSpan(text: ' \u00B7 '),
                                        TextSpan(text: '${restaurant.distanceMi!.toStringAsFixed(1)} mi'),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // DoorDash-style info chips (horizontally scrollable)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Rating chip
                            _DoorDashInfoChip(
                              topLine: '${restaurant.rating} \u2605 (${_formatCount(restaurant.reviewCount)})',
                              bottomLine: 'See reviews',
                            ),
                            const SizedBox(width: 8),
                            // Neighbors liked
                            if (restaurant.neighborsLiked != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _DoorDashInfoChip(
                                  topLine: '${restaurant.neighborsLiked} neighbors liked',
                                  bottomLine: 'Learn more',
                                ),
                              ),
                            // Customer photos
                            _DoorDashInfoChip(
                              topLine: 'Customer photos',
                              bottomLine: 'See all',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Delivery / Pickup toggle + Group Order
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.selectedDark,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('Delivery', style: AppTextStyles.labelLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      alignment: Alignment.center,
                                      child: Text('Pickup', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Group Order button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text('Group Order', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Delivery fee / time info card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            if (restaurant.deliveryFee > 0) ...[
                              Text(
                                '\$${restaurant.deliveryFee.toStringAsFixed(2)}',
                                style: AppTextStyles.priceStrikethrough,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '\$0.00',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'delivery fee over \$12 \u24D8',
                                style: AppTextStyles.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${restaurant.deliveryTimeMin} min',
                              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 2),
                            Text('delivery time', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Deals & benefits header
                      if (restaurant.promotions.isNotEmpty) ...[
                        Row(
                          children: [
                            Text('Deals & benefits', style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            const Icon(Icons.arrow_forward, size: 18, color: AppColors.textSecondary),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Horizontal scrollable deal cards
                        SizedBox(
                          height: 56,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: restaurant.promotions.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.dealTagBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.local_offer, size: 14, color: AppColors.dealTag),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 220),
                                      child: Text(
                                        restaurant.promotions[index],
                                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.dealTag, fontWeight: FontWeight.w500),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Featured Items section header
                      Text('Featured Items', style: AppTextStyles.titleLarge),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),

              // ── Category Tabs ─────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final selected = cat == _selectedCategory;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.selectedDark : AppColors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? AppColors.selectedDark : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (index == 0 && !selected)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.tune, size: 14, color: AppColors.textPrimary),
                                ),
                              if (index == 0 && !selected)
                                const Icon(Icons.search, size: 14, color: AppColors.textPrimary),
                              if (index == 0 && !selected)
                                const SizedBox(width: 4),
                              Text(
                                index == 0 ? 'Most Ordered' : cat,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: selected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ── Menu Items (2-column grid) ─────────────────
              filteredItems.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text("No items found in this category")),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.62,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filteredItems[index];
                        return _MenuGridCard(
                          item: item,
                          onAdd: () {
                            ref.read(cartProvider.notifier).addItem(
                              item.id,
                              item.name,
                              item.price,
                              imageUrl: item.imageUrl,
                              restaurantId: restaurant.id,
                              restaurantName: restaurant.name,
                              restaurantImage: restaurant.imageUrl,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${item.name} added to cart'),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          },
                          onTap: () => _showItemDetail(context, item, restaurant),
                        );
                      },
                      childCount: filteredItems.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ── Reviews section teaser ─────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('Reviews', style: AppTextStyles.titleLarge),
                      const Spacer(),
                      TextButton(
                        onPressed: () {},
                        child: Text('Add Review', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),

      // ── Sticky Bottom Cart Bar ────────────────────────
      bottomNavigationBar: cartItems.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push('/cart'),
                      borderRadius: BorderRadius.circular(30),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${cartItems.length}',
                                style: AppTextStyles.button.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'View Cart',
                              style: AppTextStyles.button.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              '\$${cartTotal.toStringAsFixed(2)}',
                              style: AppTextStyles.button.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  void _showItemDetail(BuildContext context, MenuItem item, Restaurant restaurant) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ItemDetailSheet(
        item: item,
        onAddToCart: (qty) {
          for (int i = 0; i < qty; i++) {
            ref.read(cartProvider.notifier).addItem(
              item.id,
              item.name,
              item.price,
              imageUrl: item.imageUrl,
              restaurantId: restaurant.id,
              restaurantName: restaurant.name,
              restaurantImage: restaurant.imageUrl,
            );
          }
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item.name} x$qty added to cart'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
      ),
    );
  }
}

// ── DoorDash-style Info Chip ─────────────────────────────────
class _DoorDashInfoChip extends StatelessWidget {
  final String topLine;
  final String bottomLine;

  const _DoorDashInfoChip({required this.topLine, required this.bottomLine});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            topLine,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            bottomLine,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item Detail Bottom Sheet ──────────────────────────────
class _ItemDetailSheet extends StatefulWidget {
  final MenuItem item;
  final ValueChanged<int> onAddToCart;

  const _ItemDetailSheet({required this.item, required this.onAddToCart});

  @override
  State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  int _quantity = 1;
  int _currentImageIndex = 0;
  final _specialInstructionsController = TextEditingController();

  @override
  void dispose() {
    _specialInstructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.item.images;
    final hasMultipleImages = images.length > 1;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, size: 22),
                      ),
                      const Spacer(),
                      Text('Details', style: AppTextStyles.titleMedium),
                      const Spacer(),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.bookmark_border, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Food Image Carousel
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.background,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: images.isNotEmpty
                                ? PageView.builder(
                                    itemCount: images.length,
                                    onPageChanged: (index) {
                                      setState(() {
                                        _currentImageIndex = index;
                                      });
                                    },
                                    itemBuilder: (context, index) {
                                      return CachedNetworkImage(
                                        imageUrl: images[index],
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                        errorWidget: (context, url, error) => const Icon(Icons.fastfood, size: 64, color: AppColors.primary),
                                      );
                                    },
                                  )
                                : const Icon(Icons.fastfood, size: 64, color: AppColors.primary),
                          ),
                        ),
                        if (hasMultipleImages) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (index) {
                              return Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == index
                                      ? AppColors.primary
                                      : AppColors.divider,
                                ),
                              );
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quantity Stepper
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _quantity > 1
                                ? () => setState(() => _quantity--)
                                : null,
                            icon: Icon(
                              Icons.remove,
                              color: _quantity > 1
                                  ? AppColors.textPrimary
                                  : AppColors.textHint,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Text(
                              '$_quantity',
                              style: AppTextStyles.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _quantity++),
                            icon: const Icon(Icons.add, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Name + Price Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(widget.item.name, style: AppTextStyles.titleLarge),
                      ),
                      Text(
                        '\$${(widget.item.price * _quantity).toStringAsFixed(2)}',
                        style: AppTextStyles.priceLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Description
                  if (widget.item.description.isNotEmpty)
                    Text(
                      widget.item.description,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Special Instructions
                  Text('Special Instructions',
                      style: AppTextStyles.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _specialInstructionsController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'e.g. No onions, extra sauce...',
                      hintStyle: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ADD TO BAG Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => widget.onAddToCart(_quantity),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text('ADD TO BAG', style: AppTextStyles.button),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Menu Grid Card Widget (DoorDash 2-col style) ─────────
class _MenuGridCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  const _MenuGridCard({
    required this.item,
    required this.onAdd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with "+" button overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: item.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          width: double.infinity,
                          height: 120,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            height: 120,
                            color: AppColors.primarySurface,
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 120,
                            color: AppColors.primarySurface,
                            child: const Icon(Icons.fastfood, color: AppColors.primary, size: 36),
                          ),
                        )
                      : Container(
                          height: 120,
                          width: double.infinity,
                          color: AppColors.primarySurface,
                          child: const Icon(Icons.fastfood, color: AppColors.primary, size: 36),
                        ),
                ),
                // "+" quick-add button
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add, size: 20, color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
            // Item details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AppTextStyles.titleSmall.copyWith(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${item.price.toStringAsFixed(2)}+',
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                    ),
                    // Approval rating
                    if (item.approvalPercent != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.thumb_up, size: 11, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Text(
                            '${item.approvalPercent}% (${item.approvalCount ?? 0})',
                            style: AppTextStyles.approvalRating,
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    // "Great price" badge
                    if (item.isGreatPrice)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.attach_money, size: 11, color: Color(0xFF2E7D32)),
                            Text(
                              'Great price',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontSize: 10,
                                color: const Color(0xFF2E7D32),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

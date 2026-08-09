import 'dart:async';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class StoreSearchScreen extends ConsumerStatefulWidget {
  final String restaurantId;
  final String restaurantName;
  const StoreSearchScreen(
      {super.key, required this.restaurantId, required this.restaurantName});

  @override
  ConsumerState<StoreSearchScreen> createState() => _StoreSearchScreenState();
}

class _StoreSearchScreenState extends ConsumerState<StoreSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  // Mock filters for UI match
  final _filters = [
    'Deals',
    'Brands',
    'HSA/FSA',
    'Under \$3',
    'Organic',
    'Gluten Free'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _query = query;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync =
        ref.watch(searchRestaurantItemsProvider(widget.restaurantId, _query));

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search in store',
              hintStyle:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textPrimary, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: AppColors.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            style: AppTextStyles.bodyMedium,
            onChanged: _onSearchChanged,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Filter Chips ──────────────────────────────
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: 1 + _filters.length, // +1 for Settings icon
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune, size: 16),
                  );
                }
                final filter = _filters[index - 1];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      if (filter == 'Deals') ...[
                        const Icon(Icons.local_offer,
                            size: 14, color: AppColors.textPrimary),
                        const SizedBox(width: 4),
                      ],
                      Text(filter,
                          style: AppTextStyles.bodySmall
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      if (filter == 'Brands')
                        const Icon(Icons.keyboard_arrow_down, size: 16),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Results Header ────────────────────────────
          if (_query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Results for "$_query"', // Placeholder count
                    style: AppTextStyles.titleMedium,
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text('Sort',
                            style: AppTextStyles.bodySmall
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          if (_query.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), // Light Green
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Freshness guaranteed or your money back',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFF1B5E20),
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Icon(Icons.info_outline,
                      size: 16, color: Color(0xFF1B5E20)),
                ],
              ),
            ),

          // ── Search Results Grid ───────────────────────
          Expanded(
            child: _query.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text(
                          'Search for items',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textHint),
                        ),
                      ],
                    ),
                  )
                : searchAsync.when(
                    data: (items) {
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            'No items found for "$_query"',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textHint),
                          ),
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75, // Adjust for card height
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 24,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _SearchGridItemCard(
                            item: item,
                            restaurantId: widget.restaurantId,
                            restaurantName: widget.restaurantName,
                            onAdd: () {
                              ref.read(cartProvider.notifier).addItem(
                                    item.id,
                                    item.name,
                                    item.price,
                                    restaurantId: widget.restaurantId,
                                    restaurantName: widget.restaurantName,
                                    imageUrl: item.imageUrl,
                                  );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${item.name} added to cart'),
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: AppColors.primary,
                                  width: 200,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Center(child: Text('Error: $err')),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchGridItemCard extends StatelessWidget {
  final MenuItem item;
  final String restaurantId;
  final String restaurantName;
  final VoidCallback onAdd;

  const _SearchGridItemCard(
      {required this.item,
      required this.restaurantId,
      required this.restaurantName,
      required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image Container
        Expanded(
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: item.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: AppColors.primarySurface),
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.fastfood,
                              color: AppColors.primary,
                              size: 40),
                        )
                      : const Center(
                          child: Icon(Icons.fastfood,
                              color: AppColors.primary, size: 40)),
                ),
              ),
              // Add Button Overlay (Bottom Right)
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
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add,
                        color: AppColors.primary, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Price
        Text(
          '\$${item.price.toStringAsFixed(2)}',
          style:
              AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),

        // Name
        const SizedBox(height: 4),
        Text(
          item.name,
          style: AppTextStyles.bodyMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        // Stock / Reviews (Mocked)
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF2E7D32), // Green dot
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Many in stock', // Mock status
              style: AppTextStyles.bodySmall
                  .copyWith(color: const Color(0xFF2E7D32), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '5k+ recently sold', // Mock status
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textHint, fontSize: 11),
        ),
      ],
    );
  }
}

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PickupScreen extends ConsumerStatefulWidget {
  const PickupScreen({super.key});

  @override
  ConsumerState<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends ConsumerState<PickupScreen> {
  static const _categories = [
    'All',
    'Food',
    'Groceries',
    'Convenience',
    'Pharmacy',
  ];

  final _searchController = TextEditingController();
  String _query = '';
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Restaurant> _filter(List<Restaurant> restaurants) {
    final query = _query.trim().toLowerCase();
    final category = _selectedCategory.toLowerCase();

    return restaurants.where((r) {
      final matchesCategory =
          category == 'all' || r.category.toLowerCase().contains(category);
      final matchesQuery = query.isEmpty ||
          r.name.toLowerCase().contains(query) ||
          r.category.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final restaurantsAsync = ref.watch(restaurantListProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: AppPageTitle(
                eyebrow: 'Skip delivery',
                title: 'Pickup',
                subtitle: 'Order ahead and collect when it suits you.',
              ),
            ),

            // ── Search field ───────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search pickup stores',
                    hintStyle: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textHint, size: 22),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Category filters ───────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _categories.map((category) {
                    final selected = _selectedCategory == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(category),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = category),
                        backgroundColor: AppColors.background,
                        selectedColor: AppColors.selectedDark,
                        labelStyle: TextStyle(
                          color: selected
                              ? AppColors.white
                              : AppColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide.none,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Restaurant list / states ───────────────
            restaurantsAsync.when(
              data: (restaurants) {
                final filtered = _filter(restaurants);

                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_walk,
                              size: 64, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          const Text('No pickup stores found',
                              style: AppTextStyles.titleMedium),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _query.isEmpty && _selectedCategory == 'All'
                                  ? 'There are no pickup stores available right now'
                                  : 'Try a different search or category',
                              style: AppTextStyles.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final r = filtered[index];
                      return RestaurantCard(
                        restaurant: r,
                        onTap: () => context.push('/restaurant/${r.id}'),
                      );
                    },
                    childCount: filtered.length,
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      const Text('Could not load pickup stores',
                          style: AppTextStyles.titleMedium),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(restaurantListProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 118)),
          ],
        ),
      ),
    );
  }
}

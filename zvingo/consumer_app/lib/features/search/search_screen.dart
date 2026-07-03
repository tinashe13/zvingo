import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:lottie/lottie.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_screen.g.dart';

@riverpod
Future<List<Restaurant>> searchRestaurants(SearchRestaurantsRef ref, String query) async {
  if (query.length < 2) return [];
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/catalog/search', queryParameters: {'q': query});
  return (response.data as List).map((e) => Restaurant.fromJson(e)).toList();
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final box = await Hive.openBox('search_history');
    final stored = box.get('recent', defaultValue: <dynamic>[]);
    if (mounted) {
      setState(() {
        _recentSearches = List<String>.from(stored);
      });
    }
  }

  Future<void> _saveSearch(String query) async {
    if (query.trim().isEmpty) return;
    final box = await Hive.openBox('search_history');
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10);
    }
    await box.put('recent', _recentSearches);
  }

  Future<void> _clearRecentSearches() async {
    final box = await Hive.openBox('search_history');
    await box.put('recent', <String>[]);
    if (mounted) {
      setState(() => _recentSearches = []);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // DoorDash-style search bar with X close button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  // Close button
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.close, size: 24, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  // Search field
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: (val) {
                          setState(() => _query = val.trim());
                        },
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            _saveSearch(val.trim());
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Search Zvingo',
                          hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                          prefixIcon: const Icon(Icons.search, color: AppColors.textHint, size: 20),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Show results if searching, otherwise show browse content
            if (_query.length >= 2)
              _buildSearchResults()
            else if (_query.isNotEmpty)
              _buildSearchSuggestions()
            else
              _buildBrowseContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSuggestions() {
    final suggestions = [
      _query,
      'root $_query',
      '$_query restaurant',
      '$_query near me',
    ];
    return Expanded(
      child: ListView(
        children: suggestions.map((s) => _searchSuggestionItem(s)).toList(),
      ),
    );
  }

  Widget _searchSuggestionItem(String text) {
    return InkWell(
      onTap: () {
        _searchController.text = text;
        setState(() => _query = text);
        _saveSearch(text);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.textHint, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final resultsAsync = ref.watch(searchRestaurantsProvider(_query));
    return Expanded(
      child: resultsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Search failed: $e')),
        data: (restaurants) {
          if (restaurants.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset(
                    'assets/animations/no_results.json',
                    width: 150,
                    height: 150,
                  ),
                  const SizedBox(height: 12),
                  Text('No results for "$_query"', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 6),
                  Text('Try a different search term',
                      style: AppTextStyles.bodySmall),
                ],
              ),
            );
          }

          // DoorDash-style: first show search suggestion items, then store results
          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: restaurants.length + 3, // +3 for suggestion items
            itemBuilder: (context, index) {
              // First item: direct match suggestion
              if (index == 0) {
                return _searchSuggestionItem(_query);
              }
              // Search suggestion variations
              if (index == 1) {
                return _searchSuggestionItem('$_query deals');
              }
              if (index == 2) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Divider(height: 1, color: AppColors.divider),
                );
              }

              // Store results (compact DoorDash-style)
              final r = restaurants[index - 3];
              final isFirst = index == 3;
              return _SearchResultItem(
                restaurant: r,
                isSponsored: isFirst,
                onTap: () {
                  _saveSearch(_query);
                  context.push('/restaurant/${r.id}');
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBrowseContent() {
    return Expanded(
      child: ListView(
        children: [
          // Recent searches
          if (_recentSearches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Recent Searches', style: AppTextStyles.titleMedium),
                  const Spacer(),
                  GestureDetector(
                    onTap: _clearRecentSearches,
                    child: Text(
                      'Clear',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._recentSearches.map((s) => _recentItem(s)),
            const SizedBox(height: 24),
          ],

          // Top Searches
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Top Searches', style: AppTextStyles.titleMedium),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _categoryCard(Icons.local_pizza, 'Pizza'),
                _categoryCard(Icons.lunch_dining, 'Burgers'),
                _categoryCard(Icons.ramen_dining, 'Asian'),
                _categoryCard(Icons.local_cafe, 'Coffee'),
                _categoryCard(Icons.icecream, 'Desserts'),
                _categoryCard(Icons.local_bar, 'Drinks'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentItem(String text) {
    return InkWell(
      onTap: () {
        _searchController.text = text;
        setState(() => _query = text);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.access_time, color: AppColors.textHint, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: AppTextStyles.bodyMedium)),
            const Icon(Icons.north_west, color: AppColors.textHint, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(IconData icon, String label) {
    return GestureDetector(
      onTap: () {
        _searchController.text = label;
        setState(() => _query = label);
      },
      child: Container(
        width: (MediaQuery.of(context).size.width - 48) / 3,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Compact Search Result Item (DoorDash style) ──────────
class _SearchResultItem extends StatelessWidget {
  final Restaurant restaurant;
  final bool isSponsored;
  final VoidCallback onTap;

  const _SearchResultItem({
    required this.restaurant,
    this.isSponsored = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Square logo thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: restaurant.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: restaurant.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.primarySurface),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.primarySurface,
                          child: const Icon(Icons.restaurant, size: 20, color: AppColors.textHint),
                        ),
                      )
                    : Container(
                        color: AppColors.primarySurface,
                        child: const Icon(Icons.restaurant, size: 20, color: AppColors.textHint),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Store info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          restaurant.name,
                          style: AppTextStyles.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSponsored) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Sponsored',
                            style: AppTextStyles.caption.copyWith(fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${restaurant.rating.toStringAsFixed(1)} \u2605',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (restaurant.distanceMi != null) ...[
                        Text(' \u00B7 ', style: AppTextStyles.bodySmall),
                        Text(
                          '${restaurant.distanceMi!.toStringAsFixed(1)} mi',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    restaurant.category,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

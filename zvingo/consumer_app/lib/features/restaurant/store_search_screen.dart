import 'dart:async';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How in-store results are ordered.
enum StoreSortOption {
  relevance('Best match'),
  priceLowToHigh('Price: low to high'),
  priceHighToLow('Price: high to low'),
  nameAsc('Name A–Z');

  const StoreSortOption(this.label);
  final String label;
}

/// Search inside one restaurant's menu.
///
/// Every control here is wired: the category chips come from the store's own
/// menu, the price chips really filter, and sort really re-orders. Nothing on
/// this screen is decorative.
class StoreSearchScreen extends ConsumerStatefulWidget {
  const StoreSearchScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
  });

  final String restaurantId;
  final String restaurantName;

  @override
  ConsumerState<StoreSearchScreen> createState() => _StoreSearchScreenState();
}

class _StoreSearchScreenState extends ConsumerState<StoreSearchScreen> {
  static const Duration _debounceWindow = Duration(milliseconds: 280);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  double? _maxPrice;
  StoreSortOption _sort = StoreSortOption.relevance;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _query = '');
      return;
    }
    _debounce = Timer(_debounceWindow, () {
      if (mounted) setState(() => _query = trimmed);
    });
  }

  void _useTerm(String term) {
    _controller.text = term;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _debounce?.cancel();
    setState(() => _query = term);
  }

  List<MenuItem> _refine(List<MenuItem> items) {
    var out = items;
    if (_maxPrice != null) {
      out = out.where((item) => item.price <= _maxPrice!).toList();
    } else {
      out = List<MenuItem>.of(out);
    }
    switch (_sort) {
      case StoreSortOption.relevance:
        break; // The backend already returns best-match first.
      case StoreSortOption.priceLowToHigh:
        out.sort((a, b) => a.price.compareTo(b.price));
      case StoreSortOption.priceHighToLow:
        out.sort((a, b) => b.price.compareTo(a.price));
      case StoreSortOption.nameAsc:
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return out;
  }

  void _addToCart(MenuItem item) {
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
        content: Text('${item.name} added to your cart'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickSort() async {
    final chosen = await showModalBottomSheet<StoreSortOption>(
      context: context,
      builder: (sheetContext) => ZvSheet(
        title: 'Sort results',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in StoreSortOption.values)
              AppIconTile(
                icon: option == _sort
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                title: option.label,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) setState(() => _sort = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(restaurantDetailProvider(widget.restaurantId));
    final results = ref.watch(
      searchRestaurantItemsProvider(widget.restaurantId, _query),
    );
    final searching = _query.isNotEmpty;

    return ZvScreen(
      title: 'Search the menu',
      subtitle: widget.restaurantName,
      fallbackRoute: '/restaurant/${widget.restaurantId}',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: ZvSearchField(
              controller: _controller,
              hint: 'Search ${widget.restaurantName}',
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: _onChanged,
              onClear: () => setState(() => _query = ''),
            ),
          ),
          if (searching) _refineBar(),
          Expanded(
            child: searching
                ? results.when(
                    loading: () => const ZvSkeletonList.menuItems(count: 6),
                    error: (error, _) => ZvErrorState(
                      error: error,
                      onRetry: () => ref.invalidate(
                        searchRestaurantItemsProvider(
                          widget.restaurantId,
                          _query,
                        ),
                      ),
                    ),
                    data: (items) => _resultList(_refine(items)),
                  )
                : _browse(detail),
          ),
        ],
      ),
    );
  }

  Widget _refineBar() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          _Chip(
            label: _sort.label,
            icon: Icons.swap_vert_rounded,
            selected: _sort != StoreSortOption.relevance,
            onTap: _pickSort,
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: 'Under US\$3',
            selected: _maxPrice == 3,
            onTap: () => setState(() => _maxPrice = _maxPrice == 3 ? null : 3),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: 'Under US\$5',
            selected: _maxPrice == 5,
            onTap: () => setState(() => _maxPrice = _maxPrice == 5 ? null : 5),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: 'Under US\$10',
            selected: _maxPrice == 10,
            onTap: () =>
                setState(() => _maxPrice = _maxPrice == 10 ? null : 10),
          ),
        ],
      ),
    );
  }

  /// Before anyone types: the store's own menu categories, straight from the
  /// menu we already fetched. No invented "top searches".
  Widget _browse(AsyncValue<Restaurant> detail) {
    return detail.when(
      loading: () => const ZvSkeletonList.tiles(count: 6),
      error: (error, _) => ZvErrorState(
        error: error,
        title: 'Could not load this menu',
        onRetry: () =>
            ref.invalidate(restaurantDetailProvider(widget.restaurantId)),
      ),
      data: (restaurant) {
        final categories = <String>{
          for (final item in restaurant.menu) item.category,
        }.where((c) => c.trim().isNotEmpty).toList()
          ..sort();

        if (categories.isEmpty) {
          return const ZvEmptyState(
            icon: Icons.menu_book_outlined,
            title: 'Nothing on the menu yet',
            message:
                'This restaurant has not published any items. Try another store from the home feed.',
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            ZvSectionHeader(
              title: 'Browse the menu',
              subtitle: '${restaurant.menu.length} items in '
                  '${categories.length} ${categories.length == 1 ? 'category' : 'categories'}',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final category in categories)
                    _Chip(
                      label: category,
                      selected: false,
                      onTap: () => _useTerm(category),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _resultList(List<MenuItem> items) {
    if (items.isEmpty) {
      return ZvEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No items match "$_query"',
        message: _maxPrice != null
            ? 'The price filter may be hiding matches. Clearing it usually helps.'
            : 'Try a shorter word, or browse the menu by category instead.',
        actionLabel: _maxPrice != null ? 'Clear price filter' : 'Clear search',
        onAction: () {
          if (_maxPrice != null) {
            setState(() => _maxPrice = null);
            return;
          }
          _controller.clear();
          setState(() => _query = '');
        },
      );
    }

    return ZvStaggeredListView.builder(
      itemCount: items.length + 1,
      gap: 0,
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      itemBuilder: (context, index) {
        if (index == 0) {
          return ZvSectionHeader(
            title: 'Results',
            subtitle: '${items.length} '
                '${items.length == 1 ? 'item matches' : 'items match'} "$_query"',
          );
        }
        final item = items[index - 1];
        return _MenuResultRow(item: item, onAdd: () => _addToCart(item));
      },
    );
  }
}

class _MenuResultRow extends StatelessWidget {
  const _MenuResultRow({required this.item, required this.onAdd});

  final MenuItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final available = item.isAvailable;
    return ZvCard(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.listGap,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      semanticLabel: '${item.name}, US\$${item.price.toStringAsFixed(2)}'
          '${available ? '' : ', unavailable'}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    item.description,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'US\$${item.price.toStringAsFixed(2)}',
                      style: AppTextStyles.money,
                    ),
                    if (item.isGreatPrice)
                      const ZvBadge(
                        label: 'Great price',
                        tone: ZvTone.success,
                        icon: Icons.trending_down_rounded,
                      ),
                    if (item.approvalPercent != null)
                      MetaItem(
                        icon: Icons.thumb_up_rounded,
                        label: '${item.approvalPercent}%'
                            '${item.approvalCount != null ? ' (${item.approvalCount})' : ''}',
                      ),
                    if (!available)
                      const ZvStatusChip(
                        label: 'Unavailable',
                        icon: Icons.remove_shopping_cart_rounded,
                        compact: true,
                        uppercase: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            children: [
              ZvNetworkImage(
                url: item.imageUrl,
                height: 72,
                width: 72,
                fallbackLabel: item.name,
                fallbackIcon: Icons.fastfood_rounded,
              ),
              const SizedBox(height: AppSpacing.xxs),
              ZvIconButton(
                icon: Icons.add_rounded,
                tooltip: available
                    ? 'Add ${item.name} to cart'
                    : '${item.name} is unavailable',
                background: available
                    ? AppColors.actionDefault
                    : AppColors.actionDisabledBg,
                foreground: AppColors.textOnDark,
                onPressed: available ? onAdd : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? AppColors.textOnDark : AppColors.textPrimary;
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: selected ? '$label, on' : label,
      child: Container(
        height: AppSpacing.minTapTarget - 4,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.actionDefault : AppColors.surface,
          borderRadius: AppRadius.fullAll,
          border: Border.all(
            color: selected ? AppColors.actionDefault : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: AppSpacing.xxs + 2),
            ],
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

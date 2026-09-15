/// The restaurant menu — where "I want this" starts.
///
/// Structure: a collapsing hero, a store header, then one section per menu
/// category behind a **pinned** search + category rail that tracks the scroll
/// position both ways (tap a category to jump, scroll to see the chip follow).
///
/// Ordering is gated in exactly one place — [_MenuScreenState._orderingEnabled]
/// — so a closed restaurant, a paused store and a sold-out dish all produce the
/// same outcome: the affordance is still visible, and the reason is on screen.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/cart/cart_conflict.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/checkout/order_placement_provider.dart';
import 'package:consumer_app/features/checkout/order_quote.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';
import 'package:consumer_app/features/restaurant/menu/menu_item_sheet.dart';
import 'package:consumer_app/features/restaurant/menu/menu_widgets.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MenuScreen extends ConsumerStatefulWidget {
  final String restaurantId;
  const MenuScreen({super.key, required this.restaurantId});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};

  String _query = '';
  String? _activeCategory;
  bool _titleCollapsed = false;

  static const double _heroHeight = 240;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Scroll ↔ category sync ─────────────────────────────────────

  void _onScroll() {
    if (!mounted) return;
    final collapsed = _scrollController.hasClients &&
        _scrollController.offset > _heroHeight - kToolbarHeight - 24;
    if (collapsed != _titleCollapsed) {
      setState(() => _titleCollapsed = collapsed);
    }
    if (_query.isNotEmpty) return;

    // The pinned header sits under the collapsed app bar; anything above that
    // line has scrolled past, so the last one past it is the active section.
    final threshold = MediaQuery.paddingOf(context).top + kToolbarHeight + 140;
    String? current;
    for (final entry in _sectionKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= threshold) current = entry.key;
    }
    current ??= _sectionKeys.keys.isEmpty ? null : _sectionKeys.keys.first;
    if (current != _activeCategory) {
      setState(() => _activeCategory = current);
    }
  }

  Future<void> _jumpToCategory(String category) async {
    final key = _sectionKeys[category];
    final target = key?.currentContext;
    setState(() => _activeCategory = category);
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: context.motion(AppMotion.slow),
      curve: context.motionCurve(AppMotion.standard),
      alignment: 0.0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  // ── Ordering gate ──────────────────────────────────────────────

  bool _orderingEnabled(Restaurant restaurant) => restaurant.isOpen;

  Future<void> _openItem(Restaurant restaurant, MenuItem item) async {
    final line = await showMenuItemSheet(
      context,
      item: item,
      restaurant: restaurant,
    );
    if (line == null || !mounted) return;
    await _commit(line);
  }

  Future<void> _quickAdd(Restaurant restaurant, MenuItem item) async {
    final line = CartItem(
      itemId: item.id,
      name: item.name,
      unitBasePrice: item.basePrice,
      restaurantId: restaurant.id,
      restaurantName: restaurant.name,
      imageUrl: item.imageUrl,
      restaurantImage: restaurant.imageUrl,
    );
    await _commit(line);
  }

  Future<void> _commit(CartItem line) async {
    final added = await addToCartWithConflictCheck(context, ref, line);
    if (!added || !mounted) return;
    showAddedToCartSnackBar(
      context,
      itemName: line.name,
      quantity: line.quantity,
      onViewCart: () => context.push('/cart'),
    );
  }

  // ── App-bar actions ────────────────────────────────────────────

  Future<void> _copyLink(Restaurant restaurant) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://zvingo.com/restaurant/${restaurant.id}'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Link to ${restaurant.name} copied'),
      ));
  }

  void _showStoreInfo(Restaurant restaurant) {
    final isFavourite =
        ref.read(favouritesProvider).contains(widget.restaurantId);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => ZvSheet(
        title: restaurant.name,
        subtitle: restaurant.category,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZvCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: restaurant.isOpen
                          ? Icons.check_circle_outline_rounded
                          : Icons.schedule_rounded,
                      label: restaurant.availability.label,
                      tint: restaurant.isOpen
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    if (restaurant.operatingHours != null &&
                        restaurant.operatingHours!.isNotEmpty)
                      _InfoRow(
                          icon: Icons.access_time_rounded,
                          label: restaurant.operatingHours!),
                    if (restaurant.address.isNotEmpty)
                      _InfoRow(
                          icon: Icons.place_outlined,
                          label: restaurant.address),
                    _InfoRow(
                      icon: Icons.delivery_dining_outlined,
                      label: restaurant.deliveryFeeMoney.isZero
                          ? 'Delivery fee calculated at checkout'
                          : '${restaurant.deliveryFeeMoney.format()} delivery fee',
                    ),
                    _InfoRow(
                        icon: Icons.timer_outlined,
                        label: '${restaurant.deliveryTime} typical delivery'),
                    if (restaurant.rating > 0)
                      _InfoRow(
                        icon: Icons.star_rounded,
                        tint: AppColors.rating,
                        label: '${restaurant.rating.toStringAsFixed(1)} average'
                            '${restaurant.reviewCount != null ? ' from ${restaurant.reviewCount} ratings' : ''}',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ZvButton.secondary(
                label: isFavourite
                    ? 'Remove from favourites'
                    : 'Save to favourites',
                icon: isFavourite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                onPressed: () {
                  ref
                      .read(favouritesProvider.notifier)
                      .toggle(widget.restaurantId);
                  Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              ZvButton.secondary(
                label: 'Copy link to this restaurant',
                icon: Icons.link_rounded,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _copyLink(restaurant);
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              ZvButton.secondary(
                label: 'Read reviews',
                icon: Icons.reviews_outlined,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _showReviews(restaurant);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReviews(Restaurant restaurant) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ReviewsSheet(restaurant: restaurant),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final restaurantAsync =
        ref.watch(restaurantDetailProvider(widget.restaurantId));

    return restaurantAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.surface,
        body: MenuSkeleton(),
      ),
      error: (error, _) => ZvScreen(
        title: 'Restaurant',
        fallbackRoute: '/home',
        child: Center(
          child: ZvErrorState(
            error: error,
            onRetry: () =>
                ref.invalidate(restaurantDetailProvider(widget.restaurantId)),
            secondaryActionLabel: 'Browse restaurants',
            onSecondaryAction: () => context.go('/home'),
          ),
        ),
      ),
      data: _buildMenu,
    );
  }

  Widget _buildMenu(Restaurant restaurant) {
    final cartItems = ref.watch(cartProvider);
    final cartOwner = ref.watch(cartOwnerProvider);
    final cartSubtotal = ref.watch(cartSubtotalProvider);
    final cartUnits = ref.watch(cartUnitCountProvider);
    final isFavourite =
        ref.watch(favouritesProvider).contains(widget.restaurantId);

    final ordering = _orderingEnabled(restaurant);
    final categories = restaurant.menuCategories;
    final searching = _query.trim().isNotEmpty;

    // Keep one key per category so the pinned rail can find each section.
    _sectionKeys.removeWhere((key, _) => !categories.contains(key));
    for (final category in categories) {
      _sectionKeys.putIfAbsent(category, () => GlobalKey());
    }
    _activeCategory ??= categories.isEmpty ? null : categories.first;

    final matches = searching
        ? restaurant.menu.where(_matchesQuery).toList()
        : const <MenuItem>[];

    // How many of each item are already in the cart (only when the cart is for
    // this restaurant).
    final inCart = <String, int>{};
    if (cartOwner.id == restaurant.id) {
      for (final line in cartItems) {
        inCart[line.itemId] = (inCart[line.itemId] ?? 0) + line.quantity;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _hero(restaurant, isFavourite),
          SliverToBoxAdapter(
            child: _StoreHeader(
              restaurant: restaurant,
              onSeeReviews: () => _showReviews(restaurant),
              onSeeInfo: () => _showStoreInfo(restaurant),
            ),
          ),
          if (!ordering)
            SliverToBoxAdapter(
              child: StoreClosedBanner(
                availability: restaurant.availability,
                restaurantName: restaurant.name,
                onBrowseOthers: () => context.go('/home'),
                onSchedule: restaurant.availability.acceptsScheduled
                    ? () {
                        ref.read(fulfilmentModeProvider.notifier).state =
                            FulfilmentMode.delivery;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              'Add what you want, then pick a time at checkout.',
                            ),
                          ));
                      }
                    : null,
              ),
            ),
          SliverPersistentHeader(
            pinned: true,
            delegate: MenuNavHeaderDelegate(
              categories: categories,
              selectedCategory: _activeCategory,
              onCategorySelected: _jumpToCategory,
              searchController: _searchController,
              isSearching: searching,
              topPadding: 0,
              onSearchChanged: (value) => setState(() => _query = value),
              onSearchCleared: () => setState(() => _query = ''),
            ),
          ),
          if (restaurant.menu.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ZvEmptyState(
                icon: Icons.restaurant_menu_rounded,
                title: 'No menu yet',
                message:
                    '${restaurant.name} has not published a menu on Zvingo. '
                    'Try another restaurant nearby.',
                actionLabel: 'Browse restaurants',
                onAction: () => context.go('/home'),
              ),
            )
          else if (searching)
            ..._searchResultSlivers(restaurant, matches, ordering, inCart)
          else
            ..._categorySlivers(restaurant, categories, ordering, inCart),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppSpacing.xxxl),
          ),
        ],
      ),
      bottomNavigationBar: _cartBar(
        restaurant: restaurant,
        owner: cartOwner,
        subtotal: cartSubtotal,
        units: cartUnits,
      ),
    );
  }

  bool _matchesQuery(MenuItem item) {
    final query = _query.trim().toLowerCase();
    return item.name.toLowerCase().contains(query) ||
        item.description.toLowerCase().contains(query) ||
        item.category.toLowerCase().contains(query);
  }

  // ── Slivers ────────────────────────────────────────────────────

  Widget _hero(Restaurant restaurant, bool isFavourite) {
    final heroUrl = restaurant.bannerUrl.isNotEmpty
        ? restaurant.bannerUrl
        : restaurant.imageUrl;
    return SliverAppBar(
      expandedHeight: _heroHeight,
      pinned: true,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leadingWidth: 60,
      leading: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Center(
          child: ZvIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            background: AppColors.surface,
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
        ),
      ),
      title: AnimatedOpacity(
        opacity: _titleCollapsed ? 1 : 0,
        duration: context.motion(AppMotion.fast),
        child: Text(
          restaurant.name,
          style: AppTextStyles.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      actions: [
        ZvIconButton(
          icon: isFavourite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          tooltip:
              isFavourite ? 'Remove from favourites' : 'Save to favourites',
          background: AppColors.surface,
          foreground: isFavourite ? AppColors.error : AppColors.textPrimary,
          onPressed: () =>
              ref.read(favouritesProvider.notifier).toggle(widget.restaurantId),
        ),
        const SizedBox(width: AppSpacing.xxs),
        ZvIconButton(
          icon: Icons.ios_share_rounded,
          tooltip: 'Copy link to this restaurant',
          background: AppColors.surface,
          onPressed: () => _copyLink(restaurant),
        ),
        const SizedBox(width: AppSpacing.xxs),
        ZvIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'Restaurant information',
          background: AppColors.surface,
          onPressed: () => _showStoreInfo(restaurant),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            ZvNetworkImage(
              url: heroUrl,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.zero,
              fallbackLabel: restaurant.name,
            ),
            // Keeps the white icon buttons legible on a bright photo.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.neutral900.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.5],
                ),
              ),
            ),
            if (!restaurant.isOpen)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.neutral900.withValues(alpha: 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _categorySlivers(
    Restaurant restaurant,
    List<String> categories,
    bool ordering,
    Map<String, int> inCart,
  ) {
    final slivers = <Widget>[];
    for (final category in categories) {
      final items =
          restaurant.menu.where((i) => i.category == category).toList();
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            key: _sectionKeys[category],
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.xl, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text(category, style: AppTextStyles.h2)),
                Text(
                  '${items.length} item${items.length == 1 ? '' : 's'}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: ZvStaggeredSliverList(
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _row(restaurant, items[index], ordering, inCart),
          ),
        ),
      );
    }
    return slivers;
  }

  List<Widget> _searchResultSlivers(
    Restaurant restaurant,
    List<MenuItem> matches,
    bool ordering,
    Map<String, int> inCart,
  ) {
    if (matches.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: ZvEmptyState(
            icon: Icons.search_off_rounded,
            title: 'Nothing matches "${_query.trim()}"',
            message: 'Try a shorter word, or clear the search to see the '
                'whole menu again.',
            actionLabel: 'Clear search',
            onAction: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
          child: Text(
            '${matches.length} result${matches.length == 1 ? '' : 's'} '
            'for "${_query.trim()}"',
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        sliver: ZvStaggeredSliverList(
          itemCount: matches.length,
          itemBuilder: (context, index) =>
              _row(restaurant, matches[index], ordering, inCart),
        ),
      ),
    ];
  }

  Widget _row(
    Restaurant restaurant,
    MenuItem item,
    bool ordering,
    Map<String, int> inCart,
  ) {
    return MenuItemRow(
      item: item,
      orderingEnabled: ordering,
      inCartQuantity: inCart[item.id] ?? 0,
      onTap: () => _openItem(restaurant, item),
      onQuickAdd: item.hasOptions ? null : () => _quickAdd(restaurant, item),
    );
  }

  Widget? _cartBar({
    required Restaurant restaurant,
    required CartOwner owner,
    required Money subtotal,
    required int units,
  }) {
    if (units == 0) return null;
    if (owner.id != null && owner.id != restaurant.id) {
      return OtherCartBar(
        restaurantName: owner.name ?? 'another restaurant',
        total: subtotal,
        itemCount: units,
        onTap: () => context.push('/cart'),
      );
    }
    return ZvStickyFooter(
      child: ZvCartBar(
        itemCount: units,
        total: subtotal.major,
        currency: subtotal.symbol,
        restaurantName: restaurant.name,
        margin: EdgeInsets.zero,
        onTap: () => context.push('/cart'),
      ),
    );
  }
}

// ── Store header ─────────────────────────────────────────────────

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({
    required this.restaurant,
    required this.onSeeReviews,
    required this.onSeeInfo,
  });

  final Restaurant restaurant;
  final VoidCallback onSeeReviews;
  final VoidCallback onSeeInfo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(restaurant.name, style: AppTextStyles.h1),
              ),
              const SizedBox(width: AppSpacing.xs),
              ZvStatusChip(
                label: restaurant.isOpen ? 'Open' : 'Closed',
                tone: restaurant.isOpen ? ZvTone.success : ZvTone.warning,
                icon: restaurant.isOpen
                    ? Icons.check_circle_outline_rounded
                    : Icons.schedule_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            restaurant.category,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          ZvMetaRow(items: [
            if (restaurant.rating > 0)
              ZvMetaItem(
                icon: Icons.star_rounded,
                tint: AppColors.rating,
                label: restaurant.reviewCount != null
                    ? '${restaurant.rating.toStringAsFixed(1)} (${restaurant.reviewCount})'
                    : restaurant.rating.toStringAsFixed(1),
              ),
            ZvMetaItem(
              icon: Icons.schedule_rounded,
              label: restaurant.deliveryTime,
            ),
            ZvMetaItem(
              icon: Icons.delivery_dining_outlined,
              label: restaurant.deliveryFeeMoney.isZero
                  ? 'Fee at checkout'
                  : '${restaurant.deliveryFeeMoney.format()} delivery',
            ),
            if (restaurant.distanceMi != null)
              ZvMetaItem(
                icon: Icons.near_me_outlined,
                label: '${restaurant.distanceMi!.toStringAsFixed(1)} mi',
              ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ZvButton.secondary(
                  label: 'Reviews',
                  icon: Icons.reviews_outlined,
                  onPressed: onSeeReviews,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ZvButton.secondary(
                  label: 'Store info',
                  icon: Icons.info_outline_rounded,
                  onPressed: onSeeInfo,
                ),
              ),
            ],
          ),
          if (restaurant.promotions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Deals here', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final promo in restaurant.promotions)
                  ZvBadge.deal(label: promo),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint ?? AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}

// ── Reviews sheet ────────────────────────────────────────────────

class _ReviewsSheet extends ConsumerWidget {
  const _ReviewsSheet({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(restaurantReviewsProvider(restaurant.id));
    return ZvSheet(
      title: 'Reviews',
      subtitle: restaurant.rating > 0
          ? '${restaurant.rating.toStringAsFixed(1)} average for ${restaurant.name}'
          : restaurant.name,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: reviewsAsync.when(
          loading: () => const ZvSkeletonList.tiles(count: 4),
          error: (error, _) => Center(
            child: ZvErrorState(
              error: error,
              compact: true,
              onRetry: () =>
                  ref.invalidate(restaurantReviewsProvider(restaurant.id)),
            ),
          ),
          data: (reviews) {
            if (reviews.isEmpty) {
              return const ZvEmptyState(
                icon: Icons.reviews_outlined,
                title: 'No reviews yet',
                message:
                    'Once people have ordered here, their ratings show up in '
                    'this list. Order and you could be the first to review.',
              );
            }
            return ZvStaggeredListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              itemCount: reviews.length,
              itemBuilder: (context, index) {
                final review = reviews[index];
                return ZvCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var star = 1; star <= 5; star++)
                            Icon(
                              star <= review.rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 16,
                              color: AppColors.rating,
                            ),
                          const Spacer(),
                          if (review.createdAt != null)
                            Text(
                              _relative(review.createdAt!),
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                      if (review.comment != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(review.comment!, style: AppTextStyles.body),
                      ],
                      if (review.tags.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xxs,
                          children: [
                            for (final tag in review.tags)
                              ZvStatusChip(
                                  label: tag, compact: true, uppercase: false),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _relative(DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 30) return '$days days ago';
    if (days < 365) return '${(days / 30).floor()} months ago';
    return '${(days / 365).floor()} years ago';
  }
}

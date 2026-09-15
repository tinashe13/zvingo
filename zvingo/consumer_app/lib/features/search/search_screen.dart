import 'dart:async';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/home/widgets/category_row.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

/// Catalog search.
///
/// Typing never blocks: the field updates on every keystroke and only the
/// network call is debounced. Below the field the screen is always in exactly
/// one of four states — browse (recents + popular), suggestions (while the
/// debounce settles), results (restaurants and dishes, grouped), or a
/// dead-end-free empty state.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.embedded = false});

  /// True when hosted by the tab shell, which supplies its own chrome.
  final bool embedded;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const Duration _debounceWindow = Duration(milliseconds: 280);
  static const String _historyBox = 'search_history';
  static const String _historyKey = 'recent';
  static const int _historyLimit = 8;
  static const double _dockInset = 118;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  /// What the user has typed — updated synchronously on every keystroke.
  String _input = '';

  /// What has actually been sent to the backend.
  String _query = '';

  List<String> _recent = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final box = await Hive.openBox<dynamic>(_historyBox);
      final stored = box.get(_historyKey, defaultValue: <dynamic>[]);
      if (!mounted) return;
      setState(() => _recent = List<String>.from(stored as List));
    } catch (_) {
      // A corrupt history box must never stop someone searching.
    }
  }

  Future<void> _remember(String term) async {
    final value = term.trim();
    if (value.isEmpty) return;
    final updated = <String>[
      value,
      ..._recent.where((e) => e.toLowerCase() != value.toLowerCase()),
    ].take(_historyLimit).toList();
    if (mounted) setState(() => _recent = updated);
    try {
      final box = await Hive.openBox<dynamic>(_historyBox);
      await box.put(_historyKey, updated);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> _forget(String? term) async {
    final updated = term == null
        ? const <String>[]
        : _recent.where((e) => e != term).toList();
    if (mounted) setState(() => _recent = updated);
    try {
      final box = await Hive.openBox<dynamic>(_historyBox);
      await box.put(_historyKey, updated);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  void _onChanged(String value) {
    setState(() => _input = value);
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

  void _submit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _debounce?.cancel();
    setState(() {
      _input = trimmed;
      _query = trimmed;
    });
    _remember(trimmed);
    _focusNode.unfocus();
  }

  void _useTerm(String term) {
    _controller.text = term;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _submit(term);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _input = '';
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(filtersProvider);
    final location = ref.watch(deliveryLocationNotifierProvider);
    final trimmed = _input.trim();
    final settled = trimmed.isNotEmpty && trimmed == _query;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              if (!widget.embedded) ...[
                ZvIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: ZvSearchField(
                  controller: _controller,
                  focusNode: _focusNode,
                  hint: 'Search restaurants or dishes',
                  autofocus: !widget.embedded,
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                  onClear: _clear,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _SearchFilterButton(
                count: filters.activeCount,
                onTap: () => context.push('/filters'),
              ),
            ],
          ),
        ),
        Expanded(
          child: trimmed.isEmpty
              ? _browse()
              : settled
                  ? _results(filters, location)
                  : _suggestions(trimmed),
        ),
      ],
    );

    if (widget.embedded) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(bottom: false, child: body),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: body),
    );
  }

  // ── Browse (no query) ───────────────────────────────────────────────────

  Widget _browse() {
    return ListView(
      padding: const EdgeInsets.only(bottom: _dockInset),
      children: [
        if (_recent.isNotEmpty) ...[
          ZvSectionHeader(
            title: 'Recent searches',
            actionLabel: 'Clear',
            onAction: () => _forget(null),
          ),
          ZvStaggeredList(
            gap: 0,
            children: [
              for (final term in _recent)
                _RecentRow(
                  term: term,
                  onTap: () => _useTerm(term),
                  onRemove: () => _forget(term),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const ZvSectionHeader(
          title: 'Popular searches',
          subtitle: 'What people order most on Zvingo',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final category in kDiscoveryCategories)
                _TermChip(
                  label: category.label,
                  icon: category.icon,
                  onTap: () => _useTerm(category.label),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Suggestions (typing, before the debounce settles) ───────────────────

  List<String> _suggestionsFor(String text) {
    final needle = text.toLowerCase();
    final seen = <String>{};
    final out = <String>[];
    void add(String value) {
      if (seen.add(value.toLowerCase())) out.add(value);
    }

    add(text);
    for (final term in _recent) {
      if (term.toLowerCase().contains(needle)) add(term);
    }
    for (final category in kDiscoveryCategories) {
      if (category.label.toLowerCase().contains(needle)) add(category.label);
    }
    return out.take(8).toList();
  }

  Widget _suggestions(String text) {
    final suggestions = _suggestionsFor(text);
    return ListView(
      padding: const EdgeInsets.only(bottom: _dockInset),
      children: [
        for (var i = 0; i < suggestions.length; i++)
          ZvEntrance(
            index: i,
            child: _SuggestionRow(
              term: suggestions[i],
              isFreeText: i == 0,
              onTap: () => _useTerm(suggestions[i]),
            ),
          ),
      ],
    );
  }

  // ── Results ─────────────────────────────────────────────────────────────

  Widget _results(FilterState filters, DeliveryLocation? location) {
    final key = SearchQuery(
      text: _query,
      discovery: DiscoveryQuery.from(filters, location),
    );
    final results = ref.watch(catalogSearchProvider(key));

    return results.when(
      loading: () => const _SearchSkeleton(),
      error: (error, _) => ZvErrorState(
        error: error,
        onRetry: () => ref.invalidate(catalogSearchProvider(key)),
        secondaryActionLabel: 'Clear search',
        onSecondaryAction: _clear,
      ),
      data: (data) {
        if (data.isEmpty) return _noResults(filters);

        final rows = <Widget>[];
        if (data.stores.isNotEmpty) {
          rows.add(
            ZvSectionHeader(
              title: 'Restaurants',
              subtitle: data.stores.length == 1
                  ? '1 match'
                  : '${data.stores.length} matches',
            ),
          );
          for (final store in data.stores) {
            rows.add(
              RestaurantCard.discovery(
                store,
                onTap: () {
                  _remember(_query);
                  context.push('/restaurant/${store.id}');
                },
              ),
            );
          }
        }
        if (data.dishes.isNotEmpty) {
          rows.add(
            ZvSectionHeader(
              title: 'Dishes',
              subtitle: '${data.dishes.length} '
                  '${data.dishes.length == 1 ? 'dish matches' : 'dishes match'} "$_query"',
            ),
          );
          for (final hit in data.dishes) {
            rows.add(
              _DishRow(
                hit: hit,
                onTap: () {
                  _remember(_query);
                  context.push('/restaurant/${hit.store.id}');
                },
              ),
            );
          }
        }

        return ZvStaggeredListView.builder(
          itemCount: rows.length,
          gap: 0,
          padding: const EdgeInsets.only(bottom: _dockInset),
          itemBuilder: (context, index) => rows[index],
        );
      },
    );
  }

  /// Never a dead end: names what failed and offers three ways forward.
  Widget _noResults(FilterState filters) {
    return ListView(
      padding: const EdgeInsets.only(bottom: _dockInset),
      children: [
        ZvEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matches for "$_query"',
          message: filters.hasActiveFilters
              ? 'You have ${filters.activeCount} filters on, which may be hiding results. Try clearing them or searching for something broader.'
              : 'Check the spelling, or try a broader term like the cuisine instead of the dish.',
          actionLabel:
              filters.hasActiveFilters ? 'Clear filters' : 'Clear search',
          onAction: () {
            if (filters.hasActiveFilters) {
              ref.read(filtersProvider.notifier).reset();
            } else {
              _clear();
            }
          },
          secondaryActionLabel: 'Browse everything',
          onSecondaryAction: () {
            _clear();
            context.go('/home');
          },
        ),
        const ZvSectionHeader(title: 'Try one of these instead'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final category in kDiscoveryCategories.take(6))
                _TermChip(
                  label: category.label,
                  icon: category.icon,
                  onTap: () => _useTerm(category.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Rows ──────────────────────────────────────────────────────────────────

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.term,
    required this.onTap,
    required this.onRemove,
  });

  final String term;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Search again for $term',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  term,
                  style: AppTextStyles.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            ZvIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Remove $term from recent searches',
              background: Colors.transparent,
              foreground: AppColors.textSecondary,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.term,
    required this.isFreeText,
    required this.onTap,
  });

  final String term;
  final bool isFreeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Search for $term',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              isFreeText ? Icons.search_rounded : Icons.trending_up_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                term,
                style: AppTextStyles.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.north_west_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.hit, required this.onTap});

  final DishHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = hit.store;
    return ZvCard(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.listGap,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: onTap,
      semanticLabel: '${hit.dish} at ${store.name}',
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: const BoxDecoration(
              color: AppColors.brandGreenSurface,
              borderRadius: AppRadius.mdAll,
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: AppColors.brandGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.dish,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  store.name,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MetaItem(
                      icon: Icons.star_rounded,
                      label: store.restaurant.rating.toStringAsFixed(1),
                      tint: AppColors.rating,
                    ),
                    MetaItem(
                      icon: Icons.schedule_rounded,
                      label: store.restaurant.deliveryTime,
                    ),
                    if (store.distanceLabel != null)
                      MetaItem(
                        icon: Icons.place_outlined,
                        label: store.distanceLabel!,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (store.isClosed)
            ZvStatusChip(
              label: store.availability.closedLabel,
              icon: Icons.schedule_rounded,
              compact: true,
              uppercase: false,
            )
          else
            const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _TermChip extends StatelessWidget {
  const _TermChip({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Search for $label',
      child: Container(
        height: AppSpacing.minTapTarget,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.fullAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(label, style: AppTextStyles.bodyStrong),
          ],
        ),
      ),
    );
  }
}

class _SearchFilterButton extends StatelessWidget {
  const _SearchFilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return ZvTapScale(
      onTap: onTap,
      semanticLabel:
          active ? '$count filters applied. Change filters' : 'Filters',
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: active ? AppColors.actionDefault : AppColors.surface,
          borderRadius: AppRadius.fullAll,
          border: Border.all(
            color: active ? AppColors.actionDefault : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 20,
              color: active ? AppColors.textOnDark : AppColors.textPrimary,
            ),
            if (active) ...[
              const SizedBox(width: AppSpacing.xxs + 2),
              Text(
                '$count',
                style: AppTextStyles.tabular(AppTextStyles.bodyStrong)
                    .copyWith(color: AppColors.textOnDark),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Matches the results layout: a section header, then restaurant cards.
class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 118),
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: ZvShimmer(child: ZvSkeletonBox(height: 18, width: 140)),
        ),
        ZvSkeletonList.restaurants(count: 3),
        SizedBox(height: AppSpacing.md),
        ZvSkeletonList.tiles(count: 3),
      ],
    );
  }
}

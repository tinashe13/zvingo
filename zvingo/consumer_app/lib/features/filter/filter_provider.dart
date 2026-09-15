import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'filter_provider.g.dart';

/// Sentinel that lets [FilterState.copyWith] tell "leave it alone" apart from
/// "set it back to null". Without it `setMinRating(null)` is a silent no-op —
/// the user taps an active rating chip and nothing clears.
const Object _unset = Object();

enum SortOption {
  recommended('Recommended'),
  rating('Top rated'),
  deliveryTime('Fastest'),
  distance('Nearest'),
  priceLowToHigh('Lowest delivery fee'),
  priceHighToLow('Highest delivery fee');

  final String label;
  const SortOption(this.label);
}

/// Delivery-time buckets offered in the filter sheet.
enum DeliveryWindow {
  under30('Under 30 min', 30),
  under45('Under 45 min', 45),
  under60('Under 1 hour', 60);

  final String label;
  final int maxMinutes;
  const DeliveryWindow(this.label, this.maxMinutes);
}

class FilterState {
  final SortOption sortBy;
  final Set<String> dietaryNeeds;
  final Set<String> categories;
  final double? maxDeliveryFee;
  final bool freeDeliveryOnly;
  final double? minRating;

  /// Upper bound on the quoted delivery time, in minutes.
  final int? maxDeliveryMinutes;

  /// 1–4 "$" band, matching the backend's median-menu-price bands.
  final int? priceBand;

  /// Hide anything that cannot take an order right now.
  final bool openNow;

  /// Only stores running a promotion.
  final bool offersOnly;

  const FilterState({
    this.sortBy = SortOption.recommended,
    this.dietaryNeeds = const {},
    this.categories = const {},
    this.maxDeliveryFee,
    this.freeDeliveryOnly = false,
    this.minRating,
    this.maxDeliveryMinutes,
    this.priceBand,
    this.openNow = false,
    this.offersOnly = false,
  });

  FilterState copyWith({
    SortOption? sortBy,
    Set<String>? dietaryNeeds,
    Set<String>? categories,
    Object? maxDeliveryFee = _unset,
    bool? freeDeliveryOnly,
    Object? minRating = _unset,
    Object? maxDeliveryMinutes = _unset,
    Object? priceBand = _unset,
    bool? openNow,
    bool? offersOnly,
  }) {
    return FilterState(
      sortBy: sortBy ?? this.sortBy,
      dietaryNeeds: dietaryNeeds ?? this.dietaryNeeds,
      categories: categories ?? this.categories,
      maxDeliveryFee: identical(maxDeliveryFee, _unset)
          ? this.maxDeliveryFee
          : maxDeliveryFee as double?,
      freeDeliveryOnly: freeDeliveryOnly ?? this.freeDeliveryOnly,
      minRating:
          identical(minRating, _unset) ? this.minRating : minRating as double?,
      maxDeliveryMinutes: identical(maxDeliveryMinutes, _unset)
          ? this.maxDeliveryMinutes
          : maxDeliveryMinutes as int?,
      priceBand:
          identical(priceBand, _unset) ? this.priceBand : priceBand as int?,
      openNow: openNow ?? this.openNow,
      offersOnly: offersOnly ?? this.offersOnly,
    );
  }

  bool get hasActiveFilters => activeCount > 0;

  /// What the entry point badges. Sort is included because a non-default sort
  /// visibly changes the result order and the user must be able to see why.
  int get activeCount {
    int count = 0;
    if (sortBy != SortOption.recommended) count++;
    count += dietaryNeeds.length;
    count += categories.length;
    if (freeDeliveryOnly) count++;
    if (minRating != null) count++;
    if (maxDeliveryMinutes != null) count++;
    if (priceBand != null) count++;
    if (openNow) count++;
    if (offersOnly) count++;
    return count;
  }

  /// Short chips for the "active filters" strip, so clearing is obvious.
  List<FilterChipSummary> get summary {
    final chips = <FilterChipSummary>[];
    if (sortBy != SortOption.recommended) {
      chips.add(FilterChipSummary(sortBy.label, FilterFacet.sort));
    }
    if (openNow) {
      chips.add(const FilterChipSummary('Open now', FilterFacet.openNow));
    }
    if (offersOnly) {
      chips.add(const FilterChipSummary('Offers', FilterFacet.offers));
    }
    if (freeDeliveryOnly) {
      chips.add(
        const FilterChipSummary('Free delivery', FilterFacet.freeDelivery),
      );
    }
    if (minRating != null) {
      chips.add(
        FilterChipSummary(
            '${minRating!.toStringAsFixed(1)}+', FilterFacet.rating),
      );
    }
    if (maxDeliveryMinutes != null) {
      chips.add(
        FilterChipSummary(
          'Under $maxDeliveryMinutes min',
          FilterFacet.deliveryTime,
        ),
      );
    }
    if (priceBand != null) {
      chips.add(
        FilterChipSummary('\$' * priceBand!, FilterFacet.price),
      );
    }
    for (final category in categories) {
      chips.add(FilterChipSummary(category, FilterFacet.category, category));
    }
    for (final need in dietaryNeeds) {
      chips.add(FilterChipSummary(need, FilterFacet.dietary, need));
    }
    return chips;
  }
}

/// Which facet a summary chip clears when dismissed.
enum FilterFacet {
  sort,
  openNow,
  offers,
  freeDelivery,
  rating,
  deliveryTime,
  price,
  category,
  dietary,
}

class FilterChipSummary {
  const FilterChipSummary(this.label, this.facet, [this.value]);

  final String label;
  final FilterFacet facet;

  /// The set member to remove, for the multi-select facets.
  final String? value;
}

@Riverpod(keepAlive: true)
class Filters extends _$Filters {
  @override
  FilterState build() => const FilterState();

  void setSortBy(SortOption sort) {
    state = state.copyWith(sortBy: sort);
  }

  void toggleDietaryNeed(String need) {
    final updated = Set<String>.from(state.dietaryNeeds);
    if (updated.contains(need)) {
      updated.remove(need);
    } else {
      updated.add(need);
    }
    state = state.copyWith(dietaryNeeds: updated);
  }

  void toggleCategory(String category) {
    final updated = Set<String>.from(state.categories);
    if (updated.contains(category)) {
      updated.remove(category);
    } else {
      updated.add(category);
    }
    state = state.copyWith(categories: updated);
  }

  void selectCategory(String? category) {
    state = state.copyWith(
      categories: category == null ? <String>{} : {category},
    );
  }

  void setFreeDeliveryOnly(bool value) {
    state = state.copyWith(freeDeliveryOnly: value);
  }

  void setOpenNow(bool value) {
    state = state.copyWith(openNow: value);
  }

  void setOffersOnly(bool value) {
    state = state.copyWith(offersOnly: value);
  }

  void setMinRating(double? rating) {
    state = state.copyWith(minRating: rating);
  }

  void setMaxDeliveryMinutes(int? minutes) {
    state = state.copyWith(maxDeliveryMinutes: minutes);
  }

  void setPriceBand(int? band) {
    state = state.copyWith(priceBand: band);
  }

  /// Clears exactly one facet — what a dismissible summary chip calls.
  void clearFacet(FilterFacet facet, [String? value]) {
    switch (facet) {
      case FilterFacet.sort:
        setSortBy(SortOption.recommended);
      case FilterFacet.openNow:
        setOpenNow(false);
      case FilterFacet.offers:
        setOffersOnly(false);
      case FilterFacet.freeDelivery:
        setFreeDeliveryOnly(false);
      case FilterFacet.rating:
        setMinRating(null);
      case FilterFacet.deliveryTime:
        setMaxDeliveryMinutes(null);
      case FilterFacet.price:
        setPriceBand(null);
      case FilterFacet.category:
        if (value != null) toggleCategory(value);
      case FilterFacet.dietary:
        if (value != null) toggleDietaryNeed(value);
    }
  }

  void reset() {
    state = const FilterState();
  }
}

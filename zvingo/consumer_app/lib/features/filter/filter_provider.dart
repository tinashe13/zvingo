import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'filter_provider.g.dart';

enum SortOption {
  recommended('Recommended'),
  rating('Rating'),
  deliveryTime('Delivery Time'),
  distance('Distance'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low');

  final String label;
  const SortOption(this.label);
}

class FilterState {
  final SortOption sortBy;
  final Set<String> dietaryNeeds;
  final Set<String> categories;
  final double? maxDeliveryFee;
  final bool freeDeliveryOnly;
  final double? minRating;

  const FilterState({
    this.sortBy = SortOption.recommended,
    this.dietaryNeeds = const {},
    this.categories = const {},
    this.maxDeliveryFee,
    this.freeDeliveryOnly = false,
    this.minRating,
  });

  FilterState copyWith({
    SortOption? sortBy,
    Set<String>? dietaryNeeds,
    Set<String>? categories,
    double? maxDeliveryFee,
    bool? freeDeliveryOnly,
    double? minRating,
  }) {
    return FilterState(
      sortBy: sortBy ?? this.sortBy,
      dietaryNeeds: dietaryNeeds ?? this.dietaryNeeds,
      categories: categories ?? this.categories,
      maxDeliveryFee: maxDeliveryFee ?? this.maxDeliveryFee,
      freeDeliveryOnly: freeDeliveryOnly ?? this.freeDeliveryOnly,
      minRating: minRating ?? this.minRating,
    );
  }

  bool get hasActiveFilters =>
      sortBy != SortOption.recommended ||
      dietaryNeeds.isNotEmpty ||
      categories.isNotEmpty ||
      maxDeliveryFee != null ||
      freeDeliveryOnly ||
      minRating != null;

  int get activeCount {
    int count = 0;
    if (sortBy != SortOption.recommended) count++;
    count += dietaryNeeds.length;
    count += categories.length;
    if (freeDeliveryOnly) count++;
    if (minRating != null) count++;
    return count;
  }
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

  void setFreeDeliveryOnly(bool value) {
    state = state.copyWith(freeDeliveryOnly: value);
  }

  void setMinRating(double? rating) {
    state = state.copyWith(minRating: rating);
  }

  void reset() {
    state = const FilterState();
  }
}

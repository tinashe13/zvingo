import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ratings screen state.
class RatingsState {
  final double overallRating;
  final double acceptanceRate;
  final double completionRate;
  final double onTimeRate;
  final int lifetimeDeliveries;
  final List<FeedbackItem> recentFeedback;
  final bool isLoading;

  const RatingsState({
    this.overallRating = 0,
    this.acceptanceRate = 0,
    this.completionRate = 0,
    this.onTimeRate = 0,
    this.lifetimeDeliveries = 0,
    this.recentFeedback = const [],
    this.isLoading = false,
  });

  RatingsState copyWith({
    double? overallRating,
    double? acceptanceRate,
    double? completionRate,
    double? onTimeRate,
    int? lifetimeDeliveries,
    List<FeedbackItem>? recentFeedback,
    bool? isLoading,
  }) {
    return RatingsState(
      overallRating: overallRating ?? this.overallRating,
      acceptanceRate: acceptanceRate ?? this.acceptanceRate,
      completionRate: completionRate ?? this.completionRate,
      onTimeRate: onTimeRate ?? this.onTimeRate,
      lifetimeDeliveries: lifetimeDeliveries ?? this.lifetimeDeliveries,
      recentFeedback: recentFeedback ?? this.recentFeedback,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FeedbackItem {
  final String customerName;
  final double rating;
  final String comment;
  final String date;

  const FeedbackItem({
    required this.customerName,
    required this.rating,
    this.comment = '',
    required this.date,
  });
}

/// Ratings provider.
class RatingsNotifier extends StateNotifier<RatingsState> {
  RatingsNotifier()
      : super(const RatingsState(
          overallRating: 4.8,
          acceptanceRate: 92,
          completionRate: 98,
          onTimeRate: 95,
          lifetimeDeliveries: 156,
          recentFeedback: [
            FeedbackItem(
              customerName: 'John M.',
              rating: 5,
              comment: 'Very fast delivery!',
              date: '2026-02-18',
            ),
            FeedbackItem(
              customerName: 'Sarah K.',
              rating: 4,
              comment: 'Good service',
              date: '2026-02-17',
            ),
            FeedbackItem(
              customerName: 'Mike T.',
              rating: 5,
              comment: 'Friendly driver',
              date: '2026-02-16',
            ),
          ],
        ));

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    // TODO: fetch from API using /finance/driver-metrics
    await Future.delayed(const Duration(seconds: 1));
    state = state.copyWith(isLoading: false);
  }
}

final ratingsProvider =
    StateNotifierProvider<RatingsNotifier, RatingsState>((ref) {
  return RatingsNotifier();
});

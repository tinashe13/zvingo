import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../core/api_client.dart';
import '../models/earnings_models.dart';
import 'auth_provider.dart';

/// Why the ratings screen has nothing to show.
enum RatingsFailure { noSession, notFound, network, unknown }

/// One piece of customer feedback, as returned in `recent_feedback`.
class FeedbackItem {
  /// Already masked server-side to "John S." — drivers see who, not personal
  /// detail (`_mask_name` in `app/rating/router.py`).
  final String customerName;

  /// 1–5 stars.
  final int rating;

  final String comment;

  /// Structured compliments/complaints the consumer app offers as chips.
  final List<String> tags;

  final DateTime? createdAt;

  const FeedbackItem({
    required this.customerName,
    required this.rating,
    this.comment = '',
    this.tags = const [],
    this.createdAt,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      customerName: (json['customer_name'] as String?) ?? 'A customer',
      rating: (json['rating'] as num?)?.round() ?? 0,
      comment: (json['comment'] as String?) ?? '',
      tags: (json['tags'] as List? ?? const []).whereType<String>().toList(),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    );
  }

  bool get isPositive => rating >= 4;

  /// `Today` / `Yesterday` / `Mon` / `15 Sep`.
  String get relativeDate =>
      createdAt == null ? '' : DateLabels.relative(createdAt!);
}

/// A performance rate that may legitimately be unmeasurable.
///
/// `app/rating/service.py` returns `None` rather than `0` when there is
/// nothing to measure yet, specifically so a brand-new driver is not shown an
/// insulting 0%. This type carries that distinction all the way to the screen.
class DriverRate {
  final double? value;

  /// What the rate is measured over, e.g. "12 offers".
  final String basis;

  const DriverRate(this.value, {this.basis = ''});

  bool get isMeasured => value != null;

  /// `92%`, or an em dash when there is nothing to measure.
  String get formatted =>
      value == null ? '—' : '${value!.round()}%';

  /// 0–1 for a progress bar. Unmeasured rates render an empty, greyed track.
  double get fraction => ((value ?? 0) / 100).clamp(0.0, 1.0);
}

/// Ratings screen state, sourced entirely from
/// `GET /rating/drivers/{driver_id}/summary`.
class RatingsState {
  /// The driver's star average. **Null until they have been rated at all** —
  /// which is different from 0.0 and must read differently on screen.
  final double? overallRating;

  /// How many reviews carried a driver rating.
  final int ratedReviews;

  /// `{5: 12, 4: 3, …}` — how many reviews gave each star count.
  final Map<int, int> distribution;

  final DriverRate acceptanceRate;
  final DriverRate completionRate;
  final DriverRate onTimeRate;

  final int lifetimeDeliveries;
  final int deliveriesInWindow;
  final int windowDays;

  /// The published on-time promise the on-time rate is measured against.
  final int onTimeSlaMinutes;

  final List<FeedbackItem> recentFeedback;

  final bool isLoading;
  final RatingsFailure? failure;

  const RatingsState({
    this.overallRating,
    this.ratedReviews = 0,
    this.distribution = const {},
    this.acceptanceRate = const DriverRate(null),
    this.completionRate = const DriverRate(null),
    this.onTimeRate = const DriverRate(null),
    this.lifetimeDeliveries = 0,
    this.deliveriesInWindow = 0,
    this.windowDays = 30,
    this.onTimeSlaMinutes = 45,
    this.recentFeedback = const [],
    this.isLoading = false,
    this.failure,
  });

  bool get hasRating => overallRating != null && ratedReviews > 0;

  /// `4.8`, or an em dash before the first review.
  String get formattedRating =>
      hasRating ? overallRating!.toStringAsFixed(1) : '—';

  /// Largest bucket in the distribution, for scaling the bars.
  int get distributionPeak =>
      distribution.values.fold(0, (a, b) => a > b ? a : b);

  int starCount(int star) => distribution[star] ?? 0;

  /// Share of reviews at [star], 0–1.
  double starFraction(int star) =>
      ratedReviews == 0 ? 0 : starCount(star) / ratedReviews;

  /// Reviews of 4 or 5 stars as a share of all rated reviews.
  double? get happyShare =>
      ratedReviews == 0 ? null : (starCount(5) + starCount(4)) / ratedReviews;

  /// The single most useful, non-punitive thing to tell this driver right now.
  ///
  /// Framing matters here: these numbers decide whether a driver feels
  /// supported or policed. Nothing below threatens deactivation, and a driver
  /// with too little data is told that plainly instead of being scored on
  /// noise.
  String get encouragement {
    if (!hasRating) {
      return 'No ratings yet. Your first few deliveries will set your score — '
          'a friendly handover is what customers mention most.';
    }
    if (ratedReviews < 5) {
      return 'Only $ratedReviews ${ratedReviews == 1 ? 'rating' : 'ratings'} so '
          'far, so this number will move a lot. It settles as you complete '
          'more deliveries.';
    }
    final rating = overallRating!;
    if (rating >= 4.8) {
      return 'Customers rate you among the best on Zvingo. Keep doing exactly '
          'what you are doing.';
    }
    if (rating >= 4.5) {
      return 'A strong score. Most drivers who climb from here do it by '
          'messaging the customer when they are a few minutes away.';
    }
    if (rating >= 4.0) {
      return 'A solid score with room to grow. Careful handling of the food '
          'and a quick hello at the door are what move this most.';
    }
    return 'Ratings have dipped recently. Read the comments below — they '
        'usually point at one fixable thing rather than many.';
  }

  RatingsState copyWith({
    double? overallRating,
    bool clearRating = false,
    int? ratedReviews,
    Map<int, int>? distribution,
    DriverRate? acceptanceRate,
    DriverRate? completionRate,
    DriverRate? onTimeRate,
    int? lifetimeDeliveries,
    int? deliveriesInWindow,
    int? windowDays,
    int? onTimeSlaMinutes,
    List<FeedbackItem>? recentFeedback,
    bool? isLoading,
    RatingsFailure? failure,
    bool clearFailure = false,
  }) {
    return RatingsState(
      overallRating: clearRating ? null : (overallRating ?? this.overallRating),
      ratedReviews: ratedReviews ?? this.ratedReviews,
      distribution: distribution ?? this.distribution,
      acceptanceRate: acceptanceRate ?? this.acceptanceRate,
      completionRate: completionRate ?? this.completionRate,
      onTimeRate: onTimeRate ?? this.onTimeRate,
      lifetimeDeliveries: lifetimeDeliveries ?? this.lifetimeDeliveries,
      deliveriesInWindow: deliveriesInWindow ?? this.deliveriesInWindow,
      windowDays: windowDays ?? this.windowDays,
      onTimeSlaMinutes: onTimeSlaMinutes ?? this.onTimeSlaMinutes,
      recentFeedback: recentFeedback ?? this.recentFeedback,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Ratings provider.
///
/// Source of truth: `GET /rating/drivers/{driver_id}/summary`
/// (`backend/app/rating/router.py`), which agent B3 shaped to serve this
/// screen in a single call — star average, per-star breakdown, masked recent
/// comments, and the three performance rates from
/// `app.rating.service.driver_performance`.
///
/// It replaces a provider that was hard-coded to a fake 4.8★ with three
/// invented reviews and a `// TODO: fetch from API using /finance/driver-metrics`
/// pointing at an endpoint that does not exist.
class RatingsNotifier extends StateNotifier<RatingsState> {
  final ApiClient _apiClient;
  final AuthSession _session;
  String? _driverId;

  RatingsNotifier(this._apiClient, this._session, this._driverId)
      : super(const RatingsState());

  String? _resolveDriverId() {
    if (_driverId != null && _driverId!.isNotEmpty) return _driverId;
    try {
      final stored = Hive.box('settings').get('user_id') as String?;
      if (stored != null && stored.isNotEmpty) _driverId = stored;
    } catch (e) {
      debugPrint('RatingsNotifier: could not read driver id: $e');
    }
    return _driverId;
  }

  Future<void> refresh() async {
    final driverId = _resolveDriverId();
    if (driverId == null) {
      state = state.copyWith(
        isLoading: false,
        failure: RatingsFailure.noSession,
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      final response = await _session.send(
        () => _apiClient.get('/rating/drivers/$driverId/summary'),
      );
      final data = response.data;
      if (data is! Map) {
        state = state.copyWith(
          isLoading: false,
          failure: RatingsFailure.unknown,
        );
        return;
      }

      final breakdown = <int, int>{};
      final rawBreakdown = data['breakdown'];
      if (rawBreakdown is Map) {
        rawBreakdown.forEach((key, value) {
          final star = int.tryParse(key.toString());
          if (star != null && value is num) breakdown[star] = value.toInt();
        });
      }

      final feedback = (data['recent_feedback'] as List? ?? const [])
          .whereType<Map>()
          .map((f) => FeedbackItem.fromJson(Map<String, dynamic>.from(f)))
          .toList();

      final offersReceived = (data['offers_received'] as num?)?.toInt() ?? 0;
      final deliveriesInWindow =
          (data['deliveries_in_window'] as num?)?.toInt() ?? 0;
      final windowDays = (data['window_days'] as num?)?.toInt() ?? 30;
      final rating = (data['driver_rating'] as num?)?.toDouble();
      final ratedReviews = (data['rated_reviews'] as num?)?.toInt() ??
          (data['driver_review_count'] as num?)?.toInt() ??
          0;

      state = RatingsState(
        overallRating: rating,
        ratedReviews: ratedReviews,
        distribution: breakdown,
        acceptanceRate: DriverRate(
          (data['acceptance_rate'] as num?)?.toDouble(),
          basis: offersReceived > 0
              ? '$offersReceived ${offersReceived == 1 ? 'offer' : 'offers'} sent to you'
              : 'No offers counted yet',
        ),
        completionRate: DriverRate(
          (data['completion_rate'] as num?)?.toDouble(),
          basis: 'Deliveries you accepted in the last $windowDays days',
        ),
        onTimeRate: DriverRate(
          (data['on_time_rate'] as num?)?.toDouble(),
          basis:
              'Delivered within ${(data['on_time_sla_minutes'] as num?)?.toInt() ?? 45} minutes of accepting',
        ),
        lifetimeDeliveries: (data['lifetime_deliveries'] as num?)?.toInt() ?? 0,
        deliveriesInWindow: deliveriesInWindow,
        windowDays: windowDays,
        onTimeSlaMinutes: (data['on_time_sla_minutes'] as num?)?.toInt() ?? 45,
        recentFeedback: feedback,
        isLoading: false,
      );
    } on DioException catch (e) {
      debugPrint('RatingsNotifier: refresh failed: ${e.message}');
      final status = e.response?.statusCode;
      state = state.copyWith(
        isLoading: false,
        failure: switch (status) {
          404 => RatingsFailure.notFound,
          _ => switch (e.type) {
              DioExceptionType.connectionTimeout ||
              DioExceptionType.sendTimeout ||
              DioExceptionType.receiveTimeout ||
              DioExceptionType.connectionError =>
                RatingsFailure.network,
              _ => RatingsFailure.unknown,
            },
        },
      );
    } catch (e) {
      debugPrint('RatingsNotifier: refresh failed: $e');
      state = state.copyWith(isLoading: false, failure: RatingsFailure.unknown);
    }
  }
}

final ratingsProvider =
    StateNotifierProvider<RatingsNotifier, RatingsState>((ref) {
  final driverId = ref.watch(authProvider.select((a) => a.userId));
  return RatingsNotifier(
    ref.read(apiClientProvider),
    ref.read(authSessionProvider),
    driverId,
  );
});

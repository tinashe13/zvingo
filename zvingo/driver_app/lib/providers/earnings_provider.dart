import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../core/api_client.dart';
import '../models/earnings_models.dart';
import '../models/earning_record.dart';

/// Earnings screen state.
class EarningsState {
  final int todayEarningsCents;
  final int weekEarningsCents;
  final int todayTipCents;
  final int weekTipCents;
  final int todayTrips;
  final int weekTrips;
  final int cashOnHandCents;
  final int cashFloatLimitCents;
  final bool needsCashDrop;
  final List<DailySummary> dailySummaries;
  final List<DriverEarningRecord> historyRecords;
  final bool isLoading;
  final bool isLoadingHistory;
  final int historyPage;
  final int historyTotal;
  final bool hasMoreHistory;

  // Filter state
  final String? filterStartDate;
  final String? filterEndDate;
  final String? filterPaymentMethod;
  final int? filterMinAmountCents;
  final String? filterMerchantName;
  final String? filterArea;

  const EarningsState({
    this.todayEarningsCents = 0,
    this.weekEarningsCents = 0,
    this.todayTipCents = 0,
    this.weekTipCents = 0,
    this.todayTrips = 0,
    this.weekTrips = 0,
    this.cashOnHandCents = 0,
    this.cashFloatLimitCents = 5000,
    this.needsCashDrop = false,
    this.dailySummaries = const [],
    this.historyRecords = const [],
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.historyPage = 1,
    this.historyTotal = 0,
    this.hasMoreHistory = false,
    this.filterStartDate,
    this.filterEndDate,
    this.filterPaymentMethod,
    this.filterMinAmountCents,
    this.filterMerchantName,
    this.filterArea,
  });

    int get todayTotalCents => todayEarningsCents + todayTipCents;
    int get weekTotalCents => weekEarningsCents + weekTipCents;

    String get formattedTodayEarnings =>
      '\$${(todayTotalCents / 100).toStringAsFixed(2)}';
    String get formattedWeekEarnings =>
      '\$${(weekTotalCents / 100).toStringAsFixed(2)}';
  String get formattedCashOnHand =>
      '\$${(cashOnHandCents / 100).toStringAsFixed(2)}';

  EarningsState copyWith({
    int? todayEarningsCents,
    int? weekEarningsCents,
    int? todayTipCents,
    int? weekTipCents,
    int? todayTrips,
    int? weekTrips,
    int? cashOnHandCents,
    int? cashFloatLimitCents,
    bool? needsCashDrop,
    List<DailySummary>? dailySummaries,
    List<DriverEarningRecord>? historyRecords,
    bool? isLoading,
    bool? isLoadingHistory,
    int? historyPage,
    int? historyTotal,
    bool? hasMoreHistory,
    String? filterStartDate,
    bool clearStartDate = false,
    String? filterEndDate,
    bool clearEndDate = false,
    String? filterPaymentMethod,
    bool clearPaymentMethod = false,
    int? filterMinAmountCents,
    bool clearMinAmount = false,
    String? filterMerchantName,
    bool clearMerchantName = false,
    String? filterArea,
    bool clearArea = false,
  }) {
    return EarningsState(
      todayEarningsCents: todayEarningsCents ?? this.todayEarningsCents,
      weekEarningsCents: weekEarningsCents ?? this.weekEarningsCents,
      todayTipCents: todayTipCents ?? this.todayTipCents,
      weekTipCents: weekTipCents ?? this.weekTipCents,
      todayTrips: todayTrips ?? this.todayTrips,
      weekTrips: weekTrips ?? this.weekTrips,
      cashOnHandCents: cashOnHandCents ?? this.cashOnHandCents,
      cashFloatLimitCents: cashFloatLimitCents ?? this.cashFloatLimitCents,
      needsCashDrop: needsCashDrop ?? this.needsCashDrop,
      dailySummaries: dailySummaries ?? this.dailySummaries,
      historyRecords: historyRecords ?? this.historyRecords,
      isLoading: isLoading ?? this.isLoading,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      historyPage: historyPage ?? this.historyPage,
      historyTotal: historyTotal ?? this.historyTotal,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      filterStartDate:
          clearStartDate ? null : (filterStartDate ?? this.filterStartDate),
      filterEndDate:
          clearEndDate ? null : (filterEndDate ?? this.filterEndDate),
      filterPaymentMethod: clearPaymentMethod
          ? null
          : (filterPaymentMethod ?? this.filterPaymentMethod),
      filterMinAmountCents: clearMinAmount
          ? null
          : (filterMinAmountCents ?? this.filterMinAmountCents),
      filterMerchantName: clearMerchantName
          ? null
          : (filterMerchantName ?? this.filterMerchantName),
      filterArea: clearArea ? null : (filterArea ?? this.filterArea),
    );
  }
}

/// Earnings provider — fetches real data from the backend.
class EarningsNotifier extends StateNotifier<EarningsState> {
  final ApiClient _apiClient;
  String? _driverId;

  EarningsNotifier(this._apiClient, this._driverId)
      : super(const EarningsState());

  /// Try to resolve driverId from Hive if not already set.
  String? _resolveDriverId() {
    if (_driverId != null) return _driverId;
    try {
      final box = Hive.box('settings');
      _driverId = box.get('user_id') as String?;
      debugPrint('EarningsNotifier: resolved driverId=$_driverId');
    } catch (e) {
      debugPrint('EarningsNotifier: Hive error resolving driverId: $e');
    }
    return _driverId;
  }

  /// Refresh summary + daily breakdown from the API.
  Future<void> refresh() async {
    final driverId = _resolveDriverId();
    if (driverId == null) {
      debugPrint('EarningsNotifier: refresh skipped - no driverId');
      return;
    }
    state = state.copyWith(isLoading: true);

    try {
      // Fetch summary and daily in parallel
      final results = await Future.wait([
        _apiClient.getDriverEarnings(driverId),
        _apiClient.getDailyBreakdown(driverId, days: 30),
      ]);

      final summary = results[0].data;
      final dailyData = results[1].data;
      final dailyList = (dailyData is List) ? dailyData : <dynamic>[];

      final dailySummaries =
          dailyList.map((d) => DailySummary.fromJson(d)).toList();

      final cashOnHand = summary['cash_on_hand_cents'] ?? 0;

      state = state.copyWith(
        todayEarningsCents: summary['today_earnings_cents'] ?? 0,
        todayTipCents: summary['today_tip_cents'] ?? 0,
        todayTrips: summary['today_deliveries'] ?? 0,
        weekEarningsCents: summary['week_earnings_cents'] ?? 0,
        weekTipCents: summary['week_tip_cents'] ?? 0,
        weekTrips: summary['week_deliveries'] ?? 0,
        cashOnHandCents: cashOnHand,
        needsCashDrop: cashOnHand >= state.cashFloatLimitCents,
        dailySummaries: dailySummaries,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('EarningsNotifier: refresh failed: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Load paginated delivery history with current filters.
  Future<void> loadHistory({bool reset = false}) async {
    final driverId = _resolveDriverId();
    if (driverId == null) return;

    final page = reset ? 1 : state.historyPage;
    state = state.copyWith(
      isLoadingHistory: true,
      historyPage: page,
      historyRecords: reset ? [] : null,
    );

    try {
      final response = await _apiClient.getEarningsHistory(
        driverId,
        startDate: state.filterStartDate,
        endDate: state.filterEndDate,
        paymentMethod: state.filterPaymentMethod,
        minAmountCents: state.filterMinAmountCents,
        merchantName: state.filterMerchantName,
        area: state.filterArea,
        page: page,
        pageSize: 20,
      );

      final data = response.data;
      final records = (data['records'] as List)
          .map((r) => DriverEarningRecord.fromJson(r))
          .toList();

      final total = data['total'] ?? 0;
      final existing = reset ? <DriverEarningRecord>[] : state.historyRecords;
      final merged = [...existing, ...records];

      state = state.copyWith(
        historyRecords: merged,
        historyTotal: total,
        historyPage: page + 1,
        hasMoreHistory: merged.length < total,
        isLoadingHistory: false,
      );
    } catch (e) {
      debugPrint('EarningsNotifier: loadHistory failed: $e');
      state = state.copyWith(isLoadingHistory: false);
    }
  }

  /// Update filters and reload history.
  void setFilters({
    String? startDate,
    bool clearStartDate = false,
    String? endDate,
    bool clearEndDate = false,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    int? minAmountCents,
    bool clearMinAmount = false,
    String? merchantName,
    bool clearMerchantName = false,
    String? area,
    bool clearArea = false,
  }) {
    state = state.copyWith(
      filterStartDate: startDate,
      clearStartDate: clearStartDate,
      filterEndDate: endDate,
      clearEndDate: clearEndDate,
      filterPaymentMethod: paymentMethod,
      clearPaymentMethod: clearPaymentMethod,
      filterMinAmountCents: minAmountCents,
      clearMinAmount: clearMinAmount,
      filterMerchantName: merchantName,
      clearMerchantName: clearMerchantName,
      filterArea: area,
      clearArea: clearArea,
    );
    loadHistory(reset: true);
  }

  /// Clear all filters and reload.
  void clearAllFilters() {
    state = state.copyWith(
      clearStartDate: true,
      clearEndDate: true,
      clearPaymentMethod: true,
      clearMinAmount: true,
      clearMerchantName: true,
      clearArea: true,
    );
    loadHistory(reset: true);
  }
}

final earningsProvider =
    StateNotifierProvider<EarningsNotifier, EarningsState>((ref) {
  final apiClient = ref.read(apiClientProvider);
  return EarningsNotifier(apiClient, null);
});

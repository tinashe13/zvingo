import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../core/api_client.dart';
import '../models/earning_record.dart';
import '../models/earnings_models.dart';
import 'auth_provider.dart';

/// Why the earnings screen has nothing to show. Each one gets its own
/// plain-language screen — a driver must never see a blank money page.
enum EarningsFailure {
  /// No signed-in driver id to query with.
  noSession,

  /// The backend refused: `_assert_self_or_admin` in `app/finance/router.py`
  /// answers 403 when the token's subject is not the driver in the path.
  forbidden,

  /// Timed out, no data connection, or the server is down.
  network,

  /// Anything else — a 500, a malformed payload.
  unknown,
}

/// Which window the headline figure is showing.
enum EarningsPeriod {
  today,
  week,
  last30,
}

extension EarningsPeriodLabel on EarningsPeriod {
  String get label => switch (this) {
        EarningsPeriod.today => 'Today',
        EarningsPeriod.week => 'This week',
        EarningsPeriod.last30 => 'Last 30 days',
      };

  String get subtitle => switch (this) {
        EarningsPeriod.today => 'Since midnight',
        EarningsPeriod.week => 'Monday to now',
        EarningsPeriod.last30 => 'Rolling 30 days',
      };
}

/// Everything the earnings screens render.
///
/// All money is [Money] (integer minor units). Nothing in this file adds
/// `double`s, and nothing adds `tip` on top of `earnings` — see the contract
/// note on [DailySummary].
class EarningsState {
  final Money todayEarnings;
  final Money todayTips;
  final Money weekEarnings;
  final Money weekTips;
  final int todayTrips;
  final int weekTrips;

  /// Customer cash the driver is currently holding on Zvingo's behalf.
  final Money cashOnHand;

  /// Above this, the driver is asked to bank the float.
  final Money cashFloatLimit;

  /// The same week's payout read independently from the immutable ledger
  /// (`ledger_week_earnings_cents`). Null when the ledger is unavailable.
  final Money? ledgerWeekEarnings;

  /// The server's own comparison of the two. `false` means the earnings
  /// summary and the ledger disagree — surfaced, never hidden.
  final bool? ledgerMatches;

  final List<DailySummary> dailySummaries;
  final List<DriverEarningRecord> historyRecords;

  final EarningsPeriod period;

  final bool isLoading;
  final bool isLoadingHistory;
  final EarningsFailure? failure;
  final EarningsFailure? historyFailure;

  final int historyPage;
  final int historyTotal;
  final bool hasMoreHistory;

  // Filters
  final String? filterStartDate;
  final String? filterEndDate;
  final String? filterPaymentMethod;
  final int? filterMinAmountCents;
  final String? filterMerchantName;
  final String? filterArea;

  const EarningsState({
    this.todayEarnings = const Money.zero(),
    this.todayTips = const Money.zero(),
    this.weekEarnings = const Money.zero(),
    this.weekTips = const Money.zero(),
    this.todayTrips = 0,
    this.weekTrips = 0,
    this.cashOnHand = const Money.zero(),
    this.cashFloatLimit = const Money(5000),
    this.ledgerWeekEarnings,
    this.ledgerMatches,
    this.dailySummaries = const [],
    this.historyRecords = const [],
    this.period = EarningsPeriod.today,
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.failure,
    this.historyFailure,
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

  /// Take-home over the last 30 days, summed from the daily rows in cents.
  Money get last30Earnings => dailySummaries.fold(
        const Money.zero(),
        (running, day) => running + day.earnings,
      );

  Money get last30Tips => dailySummaries.fold(
        const Money.zero(),
        (running, day) => running + day.tips,
      );

  int get last30Trips =>
      dailySummaries.fold(0, (running, day) => running + day.tripCount);

  /// The headline figure for the selected [period].
  Money get periodEarnings => switch (period) {
        EarningsPeriod.today => todayEarnings,
        EarningsPeriod.week => weekEarnings,
        EarningsPeriod.last30 => last30Earnings,
      };

  Money get periodTips => switch (period) {
        EarningsPeriod.today => todayTips,
        EarningsPeriod.week => weekTips,
        EarningsPeriod.last30 => last30Tips,
      };

  int get periodTrips => switch (period) {
        EarningsPeriod.today => todayTrips,
        EarningsPeriod.week => weekTrips,
        EarningsPeriod.last30 => last30Trips,
      };

  /// The fare portion of the selected period — total minus tips. A component
  /// split, never an addition.
  Money get periodFares => periodEarnings - periodTips;

  /// Average per delivery, or null when there are no deliveries to average.
  Money? get periodPerTrip => periodTrips > 0
      ? Money(periodEarnings.cents ~/ periodTrips, periodEarnings.currency)
      : null;

  bool get needsCashDrop => cashOnHand.cents >= cashFloatLimit.cents;

  /// True when the server told us its two independent records of this week's
  /// pay disagree. The screen says so rather than picking one.
  bool get hasLedgerDiscrepancy => ledgerMatches == false;

  Money? get ledgerDiscrepancy => ledgerWeekEarnings == null
      ? null
      : ledgerWeekEarnings! - weekEarnings;

  bool get hasAnyEarnings =>
      todayTrips > 0 || weekTrips > 0 || dailySummaries.isNotEmpty;

  bool get hasActiveFilters =>
      filterStartDate != null ||
      filterEndDate != null ||
      filterPaymentMethod != null ||
      filterMinAmountCents != null ||
      filterMerchantName != null ||
      filterArea != null;

  /// History grouped by calendar day, newest first, with each day's take-home
  /// summed from its own records so the group header always agrees with the
  /// rows under it.
  List<HistoryDayGroup> get groupedHistory {
    final groups = <DateTime, List<DriverEarningRecord>>{};
    for (final record in historyRecords) {
      groups.putIfAbsent(record.day, () => []).add(record);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        HistoryDayGroup(
          day: day,
          records: groups[day]!,
        ),
    ];
  }

  EarningsState copyWith({
    Money? todayEarnings,
    Money? todayTips,
    Money? weekEarnings,
    Money? weekTips,
    int? todayTrips,
    int? weekTrips,
    Money? cashOnHand,
    Money? cashFloatLimit,
    Money? ledgerWeekEarnings,
    bool clearLedger = false,
    bool? ledgerMatches,
    List<DailySummary>? dailySummaries,
    List<DriverEarningRecord>? historyRecords,
    EarningsPeriod? period,
    bool? isLoading,
    bool? isLoadingHistory,
    EarningsFailure? failure,
    bool clearFailure = false,
    EarningsFailure? historyFailure,
    bool clearHistoryFailure = false,
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
      todayEarnings: todayEarnings ?? this.todayEarnings,
      todayTips: todayTips ?? this.todayTips,
      weekEarnings: weekEarnings ?? this.weekEarnings,
      weekTips: weekTips ?? this.weekTips,
      todayTrips: todayTrips ?? this.todayTrips,
      weekTrips: weekTrips ?? this.weekTrips,
      cashOnHand: cashOnHand ?? this.cashOnHand,
      cashFloatLimit: cashFloatLimit ?? this.cashFloatLimit,
      ledgerWeekEarnings:
          clearLedger ? null : (ledgerWeekEarnings ?? this.ledgerWeekEarnings),
      ledgerMatches: clearLedger ? null : (ledgerMatches ?? this.ledgerMatches),
      dailySummaries: dailySummaries ?? this.dailySummaries,
      historyRecords: historyRecords ?? this.historyRecords,
      period: period ?? this.period,
      isLoading: isLoading ?? this.isLoading,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      failure: clearFailure ? null : (failure ?? this.failure),
      historyFailure:
          clearHistoryFailure ? null : (historyFailure ?? this.historyFailure),
      historyPage: historyPage ?? this.historyPage,
      historyTotal: historyTotal ?? this.historyTotal,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      filterStartDate:
          clearStartDate ? null : (filterStartDate ?? this.filterStartDate),
      filterEndDate: clearEndDate ? null : (filterEndDate ?? this.filterEndDate),
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

/// One day of delivery history plus its own totals.
class HistoryDayGroup {
  final DateTime day;
  final List<DriverEarningRecord> records;

  const HistoryDayGroup({required this.day, required this.records});

  /// Sum of the rows in this group, in cents. The header renders this, so the
  /// header can never disagree with the rows beneath it.
  Money get total => records.fold(
        Money.zero(records.isEmpty ? Money.usd : records.first.total.currency),
        (running, record) => running + record.total,
      );

  Money get tips => records.fold(
        Money.zero(records.isEmpty ? Money.usd : records.first.tip.currency),
        (running, record) => running + record.tip,
      );

  int get tripCount => records.length;

  String get label => DateLabels.relative(day);

  String get fullDate => DateLabels.full(day);
}

/// Earnings provider — reads the real finance endpoints.
///
/// Endpoints (`backend/app/finance/router.py`, mounted at the root — there is
/// no `/api/v1` in a real request path):
///
/// * `GET /finance/earnings/driver/{id}` — today + week totals, cash on hand,
///   and an independent ledger reading of the same week.
/// * `GET /finance/earnings/driver/{id}/daily?days=30` — per-day aggregation.
/// * `GET /finance/earnings/driver/{id}/history` — paginated, filterable
///   per-delivery records.
///
/// All three call `_assert_self_or_admin(driver_id, current_user, …)`, so
/// asking for another driver's money is a **403**, not an empty list. That is
/// handled explicitly: a 403 gets its own screen rather than looking like
/// "you earned nothing today".
class EarningsNotifier extends StateNotifier<EarningsState> {
  final ApiClient _apiClient;
  final AuthSession _session;
  String? _driverId;

  EarningsNotifier(this._apiClient, this._session, this._driverId)
      : super(const EarningsState());

  /// Resolve the driver id from the live session, falling back to Hive.
  String? _resolveDriverId() {
    if (_driverId != null && _driverId!.isNotEmpty) return _driverId;
    try {
      final stored = Hive.box('settings').get('user_id') as String?;
      if (stored != null && stored.isNotEmpty) _driverId = stored;
    } catch (e) {
      debugPrint('EarningsNotifier: could not read driver id: $e');
    }
    return _driverId;
  }

  /// Classifies a failure so the UI can explain it in the driver's language.
  EarningsFailure _classify(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 403) return EarningsFailure.forbidden;
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return EarningsFailure.network;
        default:
          return EarningsFailure.unknown;
      }
    }
    return EarningsFailure.unknown;
  }

  void setPeriod(EarningsPeriod period) {
    if (state.period == period) return;
    state = state.copyWith(period: period);
  }

  /// Refresh the summary and the 30-day daily breakdown.
  Future<void> refresh() async {
    final driverId = _resolveDriverId();
    if (driverId == null) {
      state = state.copyWith(
        isLoading: false,
        failure: EarningsFailure.noSession,
      );
      return;
    }
    state = state.copyWith(isLoading: true, clearFailure: true);

    try {
      final results = await Future.wait([
        _session.send(() => _apiClient.getDriverEarnings(driverId)),
        _session.send(() => _apiClient.getDailyBreakdown(driverId, days: 30)),
      ]);

      final summary = results[0].data;
      if (summary is! Map) {
        state = state.copyWith(
          isLoading: false,
          failure: EarningsFailure.unknown,
        );
        return;
      }

      final dailyData = results[1].data;
      final dailySummaries = (dailyData is List)
          ? dailyData
              .whereType<Map>()
              .map((d) => DailySummary.fromJson(Map<String, dynamic>.from(d)))
              .toList()
          : <DailySummary>[];

      final currency = (summary['currency'] as String?) ?? Money.usd;
      final ledgerRaw = summary['ledger_week_earnings_cents'];

      state = state.copyWith(
        todayEarnings: Money.parse(summary['today_earnings_cents'], currency),
        todayTips: Money.parse(summary['today_tip_cents'], currency),
        todayTrips: (summary['today_deliveries'] as num?)?.toInt() ?? 0,
        weekEarnings: Money.parse(summary['week_earnings_cents'], currency),
        weekTips: Money.parse(summary['week_tip_cents'], currency),
        weekTrips: (summary['week_deliveries'] as num?)?.toInt() ?? 0,
        cashOnHand: Money.parse(summary['cash_on_hand_cents'], currency),
        ledgerWeekEarnings:
            ledgerRaw == null ? null : Money.parse(ledgerRaw, currency),
        clearLedger: ledgerRaw == null,
        ledgerMatches: summary['ledger_matches'] as bool?,
        dailySummaries: dailySummaries,
        isLoading: false,
        clearFailure: true,
      );
    } catch (e) {
      debugPrint('EarningsNotifier: refresh failed: $e');
      state = state.copyWith(isLoading: false, failure: _classify(e));
    }
  }

  /// Load a page of delivery history with the current filters.
  Future<void> loadHistory({bool reset = false}) async {
    final driverId = _resolveDriverId();
    if (driverId == null) {
      state = state.copyWith(
        isLoadingHistory: false,
        historyFailure: EarningsFailure.noSession,
      );
      return;
    }

    final page = reset ? 1 : state.historyPage;
    state = state.copyWith(
      isLoadingHistory: true,
      historyPage: page,
      historyRecords: reset ? const [] : null,
      historyTotal: reset ? 0 : null,
      clearHistoryFailure: true,
    );

    try {
      final response = await _session.send(
        () => _apiClient.getEarningsHistory(
          driverId,
          startDate: state.filterStartDate,
          endDate: state.filterEndDate,
          paymentMethod: state.filterPaymentMethod,
          minAmountCents: state.filterMinAmountCents,
          merchantName: state.filterMerchantName,
          area: state.filterArea,
          page: page,
          pageSize: 20,
        ),
      );

      final data = response.data;
      if (data is! Map) {
        state = state.copyWith(
          isLoadingHistory: false,
          historyFailure: EarningsFailure.unknown,
        );
        return;
      }

      final records = (data['records'] as List? ?? const [])
          .whereType<Map>()
          .map((r) => DriverEarningRecord.fromJson(Map<String, dynamic>.from(r)))
          .toList();

      final total = (data['total'] as num?)?.toInt() ?? 0;
      final existing = reset ? <DriverEarningRecord>[] : state.historyRecords;
      final merged = [...existing, ...records];

      state = state.copyWith(
        historyRecords: merged,
        historyTotal: total,
        historyPage: page + 1,
        // The server post-filters merchant/area *after* paging, so a page can
        // come back shorter than requested while more pages remain. Trust the
        // page count, not the accumulated length, or the last pages of a
        // filtered search become unreachable.
        hasMoreHistory: records.isNotEmpty && page * 20 < total,
        isLoadingHistory: false,
        clearHistoryFailure: true,
      );
    } catch (e) {
      debugPrint('EarningsNotifier: loadHistory failed: $e');
      state = state.copyWith(
        isLoadingHistory: false,
        historyFailure: _classify(e),
      );
    }
  }

  /// Update filters and reload from page 1.
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
  // Watching auth means signing in (or a session ending) rebuilds this
  // notifier with the right driver id, instead of it staying stuck on the
  // null it resolved at app start.
  final driverId = ref.watch(authProvider.select((a) => a.userId));
  return EarningsNotifier(
    ref.read(apiClientProvider),
    ref.read(authSessionProvider),
    driverId,
  );
});

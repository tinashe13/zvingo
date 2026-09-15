import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../models/earning_record.dart';
import '../../models/earnings_models.dart';
import '../../providers/earnings_provider.dart';
import '../../widgets/widgets.dart';
import 'earnings_reconciliation.dart';

/// Every delivery, grouped by day, filterable, each one openable.
///
/// This is the screen a driver opens when a payout does not look right. It has
/// to answer three questions without them having to ask support: *which
/// deliveries make up this total*, *what was I paid for each one*, and *how
/// was that number arrived at*. Day headers sum the rows beneath them, and
/// tapping a row opens the line-by-line breakdown.
class EarningsHistoryScreen extends ConsumerStatefulWidget {
  const EarningsHistoryScreen({super.key});

  @override
  ConsumerState<EarningsHistoryScreen> createState() =>
      _EarningsHistoryScreenState();
}

class _EarningsHistoryScreenState extends ConsumerState<EarningsHistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(() {
      if (mounted) ref.read(earningsProvider.notifier).loadHistory(reset: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 320) return;
    final state = ref.read(earningsProvider);
    if (state.isLoadingHistory || !state.hasMoreHistory) return;
    ref.read(earningsProvider.notifier).loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final earnings = ref.watch(earningsProvider);
    final notifier = ref.read(earningsProvider.notifier);
    final groups = earnings.groupedHistory;

    return Scaffold(
      appBar: DriverAppBar(
        title: 'Delivery history',
        subtitle: _subtitleFor(earnings),
        fallbackRoute: '/earnings',
        actions: [
          DriverIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filter deliveries',
            onPressed: () => _openFilters(context, earnings, notifier),
            backgroundColor: earnings.hasActiveFilters
                ? AppColors.actionOf(context)
                : null,
            foregroundColor: earnings.hasActiveFilters
                ? AppColors.onActionOf(context)
                : null,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (earnings.hasActiveFilters)
              _ActiveFilterBar(earnings: earnings, notifier: notifier),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => notifier.loadHistory(reset: true),
                child: _list(context, earnings, notifier, groups),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(EarningsState earnings) {
    if (earnings.historyTotal == 0 && earnings.isLoadingHistory) {
      return 'Loading…';
    }
    final count = earnings.historyTotal;
    final noun = count == 1 ? 'delivery' : 'deliveries';
    return earnings.hasActiveFilters
        ? '$count $noun match your filters'
        : '$count $noun';
  }

  Widget _list(
    BuildContext context,
    EarningsState earnings,
    EarningsNotifier notifier,
    List<HistoryDayGroup> groups,
  ) {
    final padding = AppSpacing.screenPaddingOf(context);

    if (earnings.historyFailure != null && earnings.historyRecords.isEmpty) {
      return ListView(
        padding: EdgeInsets.symmetric(
          horizontal: padding,
          vertical: AppSpacing.xxl,
        ),
        children: [
          _failureState(
            earnings.historyFailure!,
            () => notifier.loadHistory(reset: true),
          ),
        ],
      );
    }

    if (earnings.isLoadingHistory && earnings.historyRecords.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(padding, AppSpacing.lg, padding, padding),
        children: const [
          SkeletonList(count: 6, builder: EarningsRowSkeleton.new),
        ],
      );
    }

    if (earnings.historyRecords.isEmpty) {
      return ListView(
        padding: EdgeInsets.symmetric(
          horizontal: padding,
          vertical: AppSpacing.xxl,
        ),
        children: [
          earnings.hasActiveFilters
              ? DriverEmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No deliveries match',
                  message:
                      'Nothing in your history fits these filters. Widening the '
                      'date range usually finds it.',
                  actionLabel: 'Clear filters',
                  onAction: notifier.clearAllFilters,
                )
              : DriverEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No deliveries yet',
                  message:
                      'Once you complete a delivery it appears here within '
                      'seconds, with the full breakdown of how it was paid.',
                  actionLabel: 'Back to earnings',
                  onAction: () => Navigator.of(context).maybePop(),
                ),
        ],
      );
    }

    // Flatten groups into a single sliver-free list: a header, then its rows.
    final rows = <Widget>[];
    var entranceIndex = 0;
    for (final group in groups) {
      rows.add(
        StaggeredEntrance(
          index: entranceIndex++,
          child: _DayHeader(group: group),
        ),
      );
      for (final record in group.records) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: StaggeredEntrance(
              index: entranceIndex++,
              child: _DeliveryCard(record: record),
            ),
          ),
        );
      }
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        padding,
        AppSpacing.lg,
        padding,
        AppSpacing.section,
      ),
      children: [
        ...rows,
        if (earnings.historyFailure != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: _InlineRetry(
              message: 'Could not load more deliveries.',
              onRetry: notifier.loadHistory,
            ),
          )
        else if (earnings.hasMoreHistory)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: SkeletonList(count: 2, builder: EarningsRowSkeleton.new),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Text(
              'That is every delivery on record.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _failureState(EarningsFailure failure, VoidCallback onRetry) {
    switch (failure) {
      case EarningsFailure.forbidden:
        return DriverErrorState(
          title: 'This history is not yours to view',
          message:
              'Zvingo only shows a driver their own deliveries. Sign out and '
              'sign back in with your own account if this looks wrong.',
          onRetry: onRetry,
          technical: 'HTTP 403 from /finance/earnings/driver/{id}/history',
        );
      case EarningsFailure.noSession:
        return DriverErrorState(
          title: 'Sign in to see your deliveries',
          message:
              'We could not tell which driver you are. Signing in again will '
              'reconnect your history.',
          onRetry: onRetry,
        );
      case EarningsFailure.network:
        return DriverErrorState(
          title: 'No connection',
          message:
              'Your deliveries are safe on Zvingo — we just cannot reach them '
              'right now. Check your mobile data and try again.',
          onRetry: onRetry,
        );
      case EarningsFailure.unknown:
        return DriverErrorState(
          title: 'Could not load your history',
          message:
              'Something went wrong on our side. Your pay is unaffected. Try '
              'again in a moment.',
          onRetry: onRetry,
        );
    }
  }

  Future<void> _openFilters(
    BuildContext context,
    EarningsState earnings,
    EarningsNotifier notifier,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.brSheetTop),
      builder: (sheetContext) =>
          _FilterSheet(earnings: earnings, notifier: notifier),
    );
  }
}

// ── Day grouping ────────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final HistoryDayGroup group;

  const _DayHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.label,
                  style: AppTextStyles.onSurface(context, AppTextStyles.h3),
                ),
                Text(
                  '${group.fullDate} · ${group.tripCount} '
                  '${group.tripCount == 1 ? 'delivery' : 'deliveries'}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Gap.hMd,
          // Summed from the rows below, in cents, so the header can never
          // disagree with what is under it.
          Text(
            group.total.formatted,
            style: AppTextStyles.money.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.successOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── One delivery row ────────────────────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final DriverEarningRecord record;

  const _DeliveryCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: () => EarningsReconciliation.showDeliverySheet(context, record),
      semanticLabel:
          '${record.merchantName} at ${record.formattedTime}, paid '
          '${record.total.formatted}. Open the pay breakdown.',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: AppSpacing.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.merchantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyStrong
                            .copyWith(color: AppColors.textPrimary),
                      ),
                      Gap.xxs,
                      Text(
                        '${record.formattedTime} · '
                        '${record.formattedDistance} · '
                        '${record.shortOrderRef}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Gap.hMd,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      record.total.formatted,
                      style: AppTextStyles.money.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (record.tip.isPositive)
                      Text(
                        'incl. ${record.tip.formatted} tip',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.successOf(context)),
                      ),
                  ],
                ),
              ],
            ),
            if (record.routeDescription.isNotEmpty) ...[
              Gap.sm,
              Row(
                children: [
                  const Icon(Icons.route_rounded,
                      size: 14, color: AppColors.textTertiary),
                  Gap.hXs,
                  Expanded(
                    child: Text(
                      record.routeDescription,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
            Gap.md,
            Row(
              children: [
                StatusChip(
                  label: record.paymentLabel,
                  tone:
                      record.isCash ? StatusTone.warning : StatusTone.success,
                  icon: record.isCash
                      ? Icons.payments_outlined
                      : Icons.phone_android_rounded,
                  preserveCase: true,
                ),
                if (!record.reconciles) ...[
                  Gap.hSm,
                  const StatusChip(
                    label: 'Check this one',
                    tone: StatusTone.error,
                    icon: Icons.report_problem_outlined,
                    preserveCase: true,
                  ),
                ],
                const Spacer(),
                Text(
                  'Breakdown',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filters ─────────────────────────────────────────────────────────────────

class _ActiveFilterBar extends StatelessWidget {
  final EarningsState earnings;
  final EarningsNotifier notifier;

  const _ActiveFilterBar({required this.earnings, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (earnings.filterStartDate != null) {
      final end = earnings.filterEndDate;
      chips.add(_RemovableChip(
        label: end == null || end == earnings.filterStartDate
            ? earnings.filterStartDate!
            : '${earnings.filterStartDate} → $end',
        icon: Icons.calendar_today_rounded,
        onRemove: () => notifier.setFilters(
          clearStartDate: true,
          clearEndDate: true,
        ),
      ));
    }
    if (earnings.filterPaymentMethod != null) {
      chips.add(_RemovableChip(
        label: earnings.filterPaymentMethod!,
        icon: Icons.payments_outlined,
        onRemove: () => notifier.setFilters(clearPaymentMethod: true),
      ));
    }
    if (earnings.filterMinAmountCents != null) {
      chips.add(_RemovableChip(
        label: 'Min ${Money(earnings.filterMinAmountCents!).formatted}',
        icon: Icons.filter_alt_outlined,
        onRemove: () => notifier.setFilters(clearMinAmount: true),
      ));
    }
    if (earnings.filterMerchantName != null) {
      chips.add(_RemovableChip(
        label: earnings.filterMerchantName!,
        icon: Icons.storefront_outlined,
        onRemove: () => notifier.setFilters(clearMerchantName: true),
      ));
    }
    if (earnings.filterArea != null) {
      chips.add(_RemovableChip(
        label: earnings.filterArea!,
        icon: Icons.location_on_outlined,
        onRemove: () => notifier.setFilters(clearArea: true),
      ));
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPaddingOf(context),
        AppSpacing.sm,
        AppSpacing.screenPaddingOf(context),
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          bottom: BorderSide(color: AppColors.borderOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: chips,
            ),
          ),
          Gap.hSm,
          DriverTextButton(
            label: 'Clear',
            onPressed: notifier.clearAllFilters,
          ),
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onRemove;

  const _RemovableChip({
    required this.label,
    required this.icon,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove filter $label',
      child: TapScale(
        onTap: onRemove,
        enforceMinTarget: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceMutedOf(context),
            borderRadius: AppSpacing.brFull,
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              Gap.hXs,
              Text(
                label,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textPrimary),
              ),
              Gap.hXs,
              const Icon(Icons.close_rounded,
                  size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final EarningsState earnings;
  final EarningsNotifier notifier;

  const _FilterSheet({required this.earnings, required this.notifier});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _merchantController;
  late final TextEditingController _areaController;

  DateTimeRange? _range;
  String? _paymentMethod;
  int? _minAmountCents;

  /// The amounts a driver actually filters by, in cents.
  static const List<int> _minAmounts = [200, 500, 1000, 2000, 5000];

  static const List<({String value, String label, IconData icon})> _methods = [
    (value: 'cash', label: 'Cash', icon: Icons.payments_outlined),
    (value: 'ecocash', label: 'EcoCash', icon: Icons.phone_android_rounded),
    (value: 'onemoney', label: 'OneMoney', icon: Icons.phone_android_rounded),
    (value: 'innbucks', label: 'InnBucks', icon: Icons.phone_android_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _merchantController =
        TextEditingController(text: widget.earnings.filterMerchantName ?? '');
    _areaController =
        TextEditingController(text: widget.earnings.filterArea ?? '');
    _paymentMethod = widget.earnings.filterPaymentMethod;
    _minAmountCents = widget.earnings.filterMinAmountCents;
    final start = DateTime.tryParse(widget.earnings.filterStartDate ?? '');
    final end = DateTime.tryParse(widget.earnings.filterEndDate ?? '');
    if (start != null) {
      _range = DateTimeRange(start: start, end: end ?? start);
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _range,
      helpText: 'Deliveries between',
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _apply() {
    widget.notifier.setFilters(
      startDate: _range == null ? null : _fmt(_range!.start),
      clearStartDate: _range == null,
      endDate: _range == null ? null : _fmt(_range!.end),
      clearEndDate: _range == null,
      paymentMethod: _paymentMethod,
      clearPaymentMethod: _paymentMethod == null,
      minAmountCents: _minAmountCents,
      clearMinAmount: _minAmountCents == null,
      merchantName: _merchantController.text.trim().isEmpty
          ? null
          : _merchantController.text.trim(),
      clearMerchantName: _merchantController.text.trim().isEmpty,
      area: _areaController.text.trim().isEmpty
          ? null
          : _areaController.text.trim(),
      clearArea: _areaController.text.trim().isEmpty,
    );
    Navigator.of(context).pop();
  }

  void _reset() {
    setState(() {
      _range = null;
      _paymentMethod = null;
      _minAmountCents = null;
      _merchantController.clear();
      _areaController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Filter deliveries',
                      style:
                          AppTextStyles.onSurface(context, AppTextStyles.h2),
                    ),
                    Gap.xl,
                    const _FilterLabel('Dates'),
                    Gap.sm,
                    DriverSecondaryButton(
                      label: _range == null
                          ? 'Any date'
                          : '${_fmt(_range!.start)}  →  ${_fmt(_range!.end)}',
                      icon: Icons.calendar_today_rounded,
                      onPressed: _pickRange,
                    ),
                    Gap.xl,
                    const _FilterLabel('Paid by'),
                    Gap.sm,
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final method in _methods)
                          _ChoiceChip(
                            label: method.label,
                            icon: method.icon,
                            selected: _paymentMethod == method.value,
                            onTap: () => setState(
                              () => _paymentMethod =
                                  _paymentMethod == method.value
                                      ? null
                                      : method.value,
                            ),
                          ),
                      ],
                    ),
                    Gap.xl,
                    const _FilterLabel('Earned at least'),
                    Gap.sm,
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final amount in _minAmounts)
                          _ChoiceChip(
                            label: Money(amount).formatted,
                            icon: Icons.trending_up_rounded,
                            selected: _minAmountCents == amount,
                            onTap: () => setState(
                              () => _minAmountCents =
                                  _minAmountCents == amount ? null : amount,
                            ),
                          ),
                      ],
                    ),
                    Gap.xl,
                    const _FilterLabel('Merchant'),
                    Gap.sm,
                    TextField(
                      controller: _merchantController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Chicken Inn',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    Gap.xl,
                    const _FilterLabel('Area or suburb'),
                    Gap.sm,
                    TextField(
                      controller: _areaController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _apply(),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Avondale',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    Gap.md,
                    Text(
                      'Merchant and area are matched on the page of results '
                      'being shown, so widen your dates if something is '
                      'missing.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
            DriverActionFooter(
              supporting: DriverTextButton(
                label: 'Reset all filters',
                onPressed: _reset,
                expanded: true,
              ),
              child: DriverPrimaryButton(
                label: 'Show deliveries',
                onPressed: _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String text;

  const _FilterLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.overline.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg =
        selected ? AppColors.onActionOf(context) : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: TapScale(
        onTap: onTap,
        enforceMinTarget: false,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.actionOf(context)
                : AppColors.surfaceMutedOf(context),
            borderRadius: AppSpacing.brFull,
            border: Border.all(
              color: selected
                  ? AppColors.actionOf(context)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? Icons.check_rounded : icon, size: 16, color: fg),
              Gap.hSm,
              Text(
                label,
                style: AppTextStyles.bodyStrong.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brLg,
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          Gap.sm,
          DriverTextButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

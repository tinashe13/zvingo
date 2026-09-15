import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_motion.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../models/earnings_models.dart';
import '../../providers/earnings_provider.dart';
import '../../widgets/widgets.dart';
import 'earnings_reconciliation.dart';

/// The money screen.
///
/// A driver judges Zvingo almost entirely on whether this screen is
/// trustworthy, so the design goal is narrow and specific: **every figure on
/// it can be traced to the deliveries that produced it.** The headline total,
/// the split under it, the daily rows and the per-delivery drill-down are all
/// derived from the same integer-cent records and are checked to add up before
/// they are drawn.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(earningsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final earnings = ref.watch(earningsProvider);
    final notifier = ref.read(earningsProvider.notifier);

    return Scaffold(
      appBar: DriverAppBar(
        title: 'Earnings',
        subtitle: earnings.period.subtitle,
        showBack: false,
        actions: [
          DriverIconButton(
            icon: Icons.receipt_long_rounded,
            tooltip: 'Delivery history',
            onPressed: () => context.push('/earnings/history'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: notifier.refresh,
          child: _body(context, earnings, notifier),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    EarningsState earnings,
    EarningsNotifier notifier,
  ) {
    if (earnings.failure != null && !earnings.hasAnyEarnings) {
      return ListView(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPaddingOf(context),
          vertical: AppSpacing.xxl,
        ),
        children: [_failureState(context, earnings.failure!, notifier.refresh)],
      );
    }

    if (earnings.isLoading && !earnings.hasAnyEarnings) {
      return _EarningsSkeleton();
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPaddingOf(context),
        AppSpacing.lg,
        AppSpacing.screenPaddingOf(context),
        AppSpacing.section,
      ),
      children: [
        StaggeredEntrance(
          index: 0,
          child: _PeriodSelector(
            value: earnings.period,
            onChanged: notifier.setPeriod,
          ),
        ),
        Gap.lg,
        StaggeredEntrance(
          index: 1,
          child: _HeadlineCard(earnings: earnings),
        ),
        if (earnings.hasLedgerDiscrepancy) ...[
          Gap.md,
          StaggeredEntrance(
            index: 2,
            child: _LedgerMismatchNotice(earnings: earnings),
          ),
        ],
        if (earnings.failure != null) ...[
          Gap.md,
          StaggeredEntrance(
            index: 2,
            child: _StaleDataNotice(
              failure: earnings.failure!,
              onRetry: notifier.refresh,
            ),
          ),
        ],
        Gap.md,
        StaggeredEntrance(
          index: 3,
          child: _CashOnHandCard(earnings: earnings),
        ),
        Gap.section,
        StaggeredEntrance(
          index: 4,
          child: _SectionHeader(
            title: 'Day by day',
            trailing: '${earnings.dailySummaries.length} days',
          ),
        ),
        Gap.md,
        if (earnings.isLoading && earnings.dailySummaries.isEmpty)
          const SkeletonList(count: 4, builder: EarningsRowSkeleton.new)
        else if (earnings.dailySummaries.isEmpty)
          _NoDeliveriesYet(onViewHistory: () => context.push('/earnings/history'))
        else
          ...earnings.dailySummaries.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: StaggeredEntrance(
                    index: entry.key + 5,
                    child: _DailyRow(summary: entry.value),
                  ),
                ),
              ),
        Gap.lg,
        DriverSecondaryButton(
          label: 'See every delivery',
          icon: Icons.receipt_long_rounded,
          onPressed: () => context.push('/earnings/history'),
        ),
        Gap.md,
        _PayExplainer(),
      ],
    );
  }

  Widget _failureState(
    BuildContext context,
    EarningsFailure failure,
    VoidCallback onRetry,
  ) {
    switch (failure) {
      case EarningsFailure.forbidden:
        return DriverErrorState(
          title: 'These earnings are not yours to view',
          message:
              'Zvingo only shows a driver their own pay. Sign out and sign back '
              'in with your own account, or contact driver support if this is '
              'your account.',
          onRetry: onRetry,
          retryLabel: 'Try again',
          technical: 'HTTP 403 from /finance/earnings/driver',
        );
      case EarningsFailure.noSession:
        return DriverErrorState(
          title: 'Sign in to see your pay',
          message:
              'We could not tell which driver you are. Signing in again will '
              'reconnect your earnings.',
          onRetry: onRetry,
          retryLabel: 'Try again',
        );
      case EarningsFailure.network:
        return DriverErrorState(
          title: 'No connection',
          message:
              'Your earnings are safe on Zvingo — we just cannot reach them '
              'right now. Check your mobile data and try again.',
          onRetry: onRetry,
        );
      case EarningsFailure.unknown:
        return DriverErrorState(
          title: 'Could not load your earnings',
          message:
              'Something went wrong on our side. Your pay is unaffected. Try '
              'again in a moment.',
          onRetry: onRetry,
        );
    }
  }
}

// ── Period selector ─────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final EarningsPeriod value;
  final ValueChanged<EarningsPeriod> onChanged;

  const _PeriodSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brFull,
      ),
      child: Row(
        children: [
          for (final period in EarningsPeriod.values)
            Expanded(
              child: _PeriodTab(
                label: period.label,
                selected: period == value,
                onTap: () => onChanged(period),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: TapScale(
        onTap: onTap,
        enforceMinTarget: false,
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.fast),
          curve: AppMotion.standard,
          height: AppSpacing.minTouchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.actionOf(context) : Colors.transparent,
            borderRadius: AppSpacing.brFull,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.button.copyWith(
              fontSize: 14,
              color: selected
                  ? AppColors.onActionOf(context)
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Headline ────────────────────────────────────────────────────────────────

/// The biggest thing on the screen, and the thing every other number on it
/// must add up to.
class _HeadlineCard extends StatelessWidget {
  final EarningsState earnings;

  const _HeadlineCard({required this.earnings});

  @override
  Widget build(BuildContext context) {
    final total = earnings.periodEarnings;
    final tips = earnings.periodTips;
    final fares = earnings.periodFares;
    final trips = earnings.periodTrips;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${earnings.period.label} take-home',
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (earnings.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          Gap.sm,
          // The hero figure. Tabular, animated, and in the success token —
          // per §1.2 `AppColors.primary` is now near-black, so money-positive
          // has to say so with `success`/`brandGreen`, not with the action colour.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Semantics(
              label: '${earnings.period.label} take-home ${total.formatted}',
              child: AnimatedCount(
                value: total.cents / 100,
                formatter: (v) =>
                    Money.format((v * 100).round(), total.currency),
                style: AppTextStyles.moneyHero.copyWith(
                  color: AppColors.successOf(context),
                ),
              ),
            ),
          ),
          Gap.sm,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusChip(
                label: '$trips ${trips == 1 ? 'delivery' : 'deliveries'}',
                tone: StatusTone.neutral,
                icon: Icons.local_shipping_outlined,
                preserveCase: true,
              ),
              if (earnings.periodPerTrip != null)
                StatusChip(
                  label: '${earnings.periodPerTrip!.formatted} per delivery',
                  tone: StatusTone.neutral,
                  icon: Icons.trending_up_rounded,
                  preserveCase: true,
                ),
            ],
          ),
          Gap.lg,
          Divider(height: 1, color: AppColors.borderOf(context)),
          Gap.lg,
          // The split. These two lines are a *decomposition* of the figure
          // above, not additions to it: the backend's `earnings_cents` already
          // contains the tips it reports separately. Adding them was a real
          // bug that overstated every total by the value of its tips.
          _SplitRow(
            label: 'Delivery fees (your share)',
            amount: fares,
            icon: Icons.route_rounded,
          ),
          Gap.md,
          _SplitRow(
            label: 'Tips',
            amount: tips,
            icon: Icons.volunteer_activism_outlined,
            emphasise: tips.isPositive,
          ),
          Gap.md,
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceMutedOf(context),
              borderRadius: AppSpacing.brMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total',
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  total.formatted,
                  style: AppTextStyles.money.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  final String label;
  final Money amount;
  final IconData icon;
  final bool emphasise;

  const _SplitRow({
    required this.label,
    required this.amount,
    required this.icon,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        Gap.hSm,
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
        Text(
          amount.formatted,
          style: AppTextStyles.money.copyWith(
            color: emphasise
                ? AppColors.successOf(context)
                : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Notices ─────────────────────────────────────────────────────────────────

/// The server keeps two independent records of a driver's week: the earnings
/// summary and the immutable ledger. When it tells us they disagree, the
/// driver hears it from us first.
class _LedgerMismatchNotice extends StatelessWidget {
  final EarningsState earnings;

  const _LedgerMismatchNotice({required this.earnings});

  @override
  Widget build(BuildContext context) {
    final gap = earnings.ledgerDiscrepancy;
    return _Notice(
      tone: StatusTone.warning,
      icon: Icons.balance_rounded,
      title: 'We are double-checking this week',
      body: gap == null
          ? 'Two of our records of this week do not match yet. Your pay is not '
              'affected while we reconcile — the figure above is your earnings '
              'record.'
          : 'Our ledger reads ${earnings.ledgerWeekEarnings!.formatted} for this '
              'week, ${gap.signed} against the figure above. Your pay is not '
              'affected while we reconcile. Quote this week to support if it '
              'does not clear.',
    );
  }
}

/// Shown when a refresh failed but cached figures are still on screen — so a
/// driver knows whether they are looking at live numbers.
class _StaleDataNotice extends StatelessWidget {
  final EarningsFailure failure;
  final VoidCallback onRetry;

  const _StaleDataNotice({required this.failure, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _Notice(
      tone: StatusTone.info,
      icon: Icons.cloud_off_rounded,
      title: failure == EarningsFailure.network
          ? 'Showing your last known figures'
          : 'Could not refresh',
      body: failure == EarningsFailure.network
          ? 'No connection right now. These numbers are from your last update.'
          : 'We could not fetch the latest. These numbers are from your last '
              'update.',
      action: DriverTextButton(
        label: 'Retry',
        icon: Icons.refresh_rounded,
        onPressed: onRetry,
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final StatusTone tone;
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _Notice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      StatusTone.warning => AppColors.warningOf(context),
      StatusTone.error => AppColors.errorOf(context),
      StatusTone.success => AppColors.successOf(context),
      _ => AppColors.infoOf(context),
    };
    final surface = switch (tone) {
      StatusTone.warning => AppColors.warningSurfaceOf(context),
      StatusTone.error => AppColors.errorSurfaceOf(context),
      StatusTone.success => AppColors.successSurfaceOf(context),
      _ => AppColors.infoSurfaceOf(context),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppSpacing.brLg,
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          Gap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyStrong.copyWith(color: color),
                ),
                Gap.xs,
                Text(
                  body,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (action != null) ...[Gap.sm, action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cash on hand ────────────────────────────────────────────────────────────

/// Cash the driver is holding for Zvingo.
///
/// There is deliberately **no "Cash drop" button here**. The screen used to
/// carry one wired to `onPressed: () {}` — and the copy next to it told
/// Zvingo's drivers to deposit money "to DoorDash". No cash-drop endpoint
/// exists on the backend (see the report), so this card explains the balance
/// and how it is settled instead of pretending to record a deposit.
class _CashOnHandCard extends StatelessWidget {
  final EarningsState earnings;

  const _CashOnHandCard({required this.earnings});

  @override
  Widget build(BuildContext context) {
    final owed = earnings.cashOnHand;
    final over = earnings.needsCashDrop;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
              Gap.hSm,
              Expanded(
                child: Text(
                  'Cash you are holding',
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              if (over)
                const StatusChip(
                  label: 'Over float',
                  tone: StatusTone.warning,
                  icon: Icons.priority_high_rounded,
                ),
            ],
          ),
          Gap.md,
          AnimatedCount.currency(
            cents: owed.cents,
            symbol: owed.symbol,
            style: AppTextStyles.moneyLarge,
          ),
          Gap.sm,
          Text(
            owed.isZero
                ? 'You are not holding any of Zvingo’s cash right now.'
                : over
                    ? 'This is above the ${earnings.cashFloatLimit.formatted} float '
                        'limit. Settle it with Zvingo operations at the end of '
                        'your shift — carrying more cash is a safety risk.'
                    : 'Cash customers paid you today that is owed to Zvingo. '
                        'Settle it at the end of your shift.',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Daily rows ──────────────────────────────────────────────────────────────

class _DailyRow extends StatelessWidget {
  final DailySummary summary;

  const _DailyRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: () => EarningsReconciliation.showDaySheet(context, summary),
      semanticLabel:
          '${summary.relativeLabel()}, ${summary.earnings.formatted} from '
          '${summary.tripCount} deliveries. Open breakdown.',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: AppSpacing.cardDecoration(context),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.relativeLabel(),
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  Gap.xxs,
                  Text(
                    '${summary.displayDate} · ${summary.tripCount} '
                    '${summary.tripCount == 1 ? 'delivery' : 'deliveries'}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (summary.tips.isPositive) ...[
                    Gap.xs,
                    Text(
                      'includes ${summary.tips.formatted} in tips',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.successOf(context)),
                    ),
                  ],
                ],
              ),
            ),
            Gap.hMd,
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  summary.earnings.formatted,
                  style: AppTextStyles.money.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Gap.xxs,
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chrome ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.onSurface(context, AppTextStyles.h2),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class _NoDeliveriesYet extends StatelessWidget {
  final VoidCallback onViewHistory;

  const _NoDeliveriesYet({required this.onViewHistory});

  @override
  Widget build(BuildContext context) {
    return DriverEmptyState(
      icon: Icons.savings_outlined,
      title: 'No earnings in the last 30 days',
      message:
          'Every delivery you complete lands here within seconds, with the full '
          'breakdown of how it was paid.',
      actionLabel: 'Go online and start earning',
      onAction: () => context.go('/'),
      secondaryLabel: 'View older deliveries',
      onSecondary: onViewHistory,
    );
  }
}

/// How pay is calculated, in the driver's own terms. This is the difference
/// between "the app decided I get $8.50" and "I know why I got $8.50".
class _PayExplainer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined,
                  size: 18, color: AppColors.textSecondary),
              Gap.hSm,
              Text(
                'How your pay is worked out',
                style: AppTextStyles.bodyStrong
                    .copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          Gap.sm,
          Text(
            'The customer is charged a delivery fee based on distance. You keep '
            'the majority of that fee, and 100% of every tip. Tap any day, or '
            'any delivery in your history, to see the exact split for that '
            'trip — the numbers always add up to what you were paid.',
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Loading ─────────────────────────────────────────────────────────────────

class _EarningsSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.screenPaddingOf(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, AppSpacing.lg, padding, padding),
      children: [
        const SkeletonBox(height: AppSpacing.minTouchTarget + 8),
        Gap.lg,
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: AppSpacing.cardDecoration(context),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox.line(widthFactor: 0.35, height: 12),
              Gap.md,
              SkeletonBox(height: 44, widthFactor: 0.6),
              Gap.lg,
              SkeletonBox.line(widthFactor: 0.8),
              Gap.sm,
              SkeletonBox.line(widthFactor: 0.65),
            ],
          ),
        ),
        Gap.section,
        const SkeletonList(count: 4, builder: EarningsRowSkeleton.new),
      ],
    );
  }
}

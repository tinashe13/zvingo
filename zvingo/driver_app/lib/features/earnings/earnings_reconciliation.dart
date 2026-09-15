import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../models/earning_record.dart';
import '../../models/earnings_models.dart';
import '../../providers/earnings_provider.dart';
import '../../widgets/widgets.dart';

/// The drill-downs that make the money screen auditable.
///
/// Two sheets:
///
/// * [showDeliverySheet] — one delivery, line by line, where the lines are
///   **checked to sum to the payout** before they are drawn.
/// * [showDaySheet] — one day's total split into fares and tips, with a way
///   through to the deliveries that produced it.
///
/// Neither computes pay. Both take server-issued integer cents and show the
/// arithmetic that produced the figure the driver already sees, which is the
/// difference between a number a driver accepts and one they can check.
class EarningsReconciliation {
  EarningsReconciliation._();

  static Future<void> showDeliverySheet(
    BuildContext context,
    DriverEarningRecord record,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: AppSpacing.brSheetTop,
      ),
      builder: (context) => _DeliveryBreakdownSheet(record: record),
    );
  }

  static Future<void> showDaySheet(
    BuildContext context,
    DailySummary summary,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: AppSpacing.brSheetTop,
      ),
      builder: (context) => _DayBreakdownSheet(summary: summary),
    );
  }
}

// ── One delivery ────────────────────────────────────────────────────────────

class _DeliveryBreakdownSheet extends StatelessWidget {
  final DriverEarningRecord record;

  const _DeliveryBreakdownSheet({required this.record});

  @override
  Widget build(BuildContext context) {
    final breakdown = record.breakdown;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                record.merchantName,
                style: AppTextStyles.onSurface(context, AppTextStyles.h2),
              ),
              Gap.xs,
              Text(
                '${record.formattedDateTime} · ${record.shortOrderRef}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
              Gap.lg,
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(
                    label: record.paymentLabel,
                    tone: record.isCash
                        ? StatusTone.warning
                        : StatusTone.success,
                    icon: record.isCash
                        ? Icons.payments_outlined
                        : Icons.phone_android_rounded,
                    preserveCase: true,
                  ),
                  StatusChip(
                    label: record.formattedDistance,
                    tone: StatusTone.neutral,
                    icon: Icons.straighten_rounded,
                    preserveCase: true,
                  ),
                ],
              ),
              if (record.routeDescription.isNotEmpty) ...[
                Gap.lg,
                _RouteBlock(record: record),
              ],
              Gap.xl,
              Text(
                'How this was paid',
                style: AppTextStyles.onSurface(context, AppTextStyles.h3),
              ),
              Gap.md,
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceMutedOf(context),
                  borderRadius: AppSpacing.brLg,
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    for (var i = 0; i < breakdown.lines.length; i++) ...[
                      if (i > 0) Gap.md,
                      _BreakdownLine(line: breakdown.lines[i]),
                    ],
                    Gap.lg,
                    Divider(height: 1, color: AppColors.borderOf(context)),
                    Gap.lg,
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'You were paid',
                            style: AppTextStyles.bodyStrong
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        Text(
                          record.total.formatted,
                          style: AppTextStyles.moneyLarge.copyWith(
                            color: AppColors.successOf(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Gap.md,
              _ReconciliationVerdict(
                reconciles: breakdown.reconciles && record.reconciles,
                discrepancy: breakdown.discrepancy,
                orderRef: record.shortOrderRef,
              ),
              if (record.isCash) ...[
                Gap.md,
                _CashNote(record: record),
              ],
              Gap.xl,
              DriverSecondaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteBlock extends StatelessWidget {
  final DriverEarningRecord record;

  const _RouteBlock({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RouteLeg(
            icon: Icons.storefront_outlined,
            label: 'Picked up',
            value: record.pickupArea.isEmpty
                ? record.merchantName
                : record.pickupArea,
          ),
          Gap.md,
          _RouteLeg(
            icon: Icons.location_on_outlined,
            label: 'Dropped off',
            value: record.dropoffArea.isEmpty
                ? 'Address not recorded'
                : record.dropoffArea,
          ),
          Gap.sm,
          Text(
            'Street numbers are hidden once a delivery is complete.',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _RouteLeg extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RouteLeg({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        Gap.hSm,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.overline
                    .copyWith(color: AppColors.textTertiary),
              ),
              Gap.xxs,
              Text(
                value,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  final PayLine line;

  const _BreakdownLine({required this.line});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.label,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary),
              ),
              Gap.xxs,
              Text(
                line.explanation,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Gap.hMd,
        Text(
          line.amount.signed,
          style: AppTextStyles.money.copyWith(
            color: line.isDeduction
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Says out loud whether the lines above add up.
///
/// A silent discrepancy is the single most corrosive thing a pay screen can
/// do. If the arithmetic ever fails, the driver is told, given the exact gap,
/// and given the order reference to quote — rather than being shown numbers
/// that quietly disagree.
class _ReconciliationVerdict extends StatelessWidget {
  final bool reconciles;
  final Money discrepancy;
  final String orderRef;

  const _ReconciliationVerdict({
    required this.reconciles,
    required this.discrepancy,
    required this.orderRef,
  });

  @override
  Widget build(BuildContext context) {
    final color = reconciles
        ? AppColors.successOf(context)
        : AppColors.warningOf(context);
    final surface = reconciles
        ? AppColors.successSurfaceOf(context)
        : AppColors.warningSurfaceOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppSpacing.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reconciles
                ? Icons.check_circle_outline_rounded
                : Icons.report_problem_outlined,
            size: 18,
            color: color,
          ),
          Gap.hSm,
          Expanded(
            child: Text(
              reconciles
                  ? 'Every line above adds up to what you were paid.'
                  : 'These lines are ${discrepancy.signed} away from the payout. '
                      'Quote $orderRef to driver support and we will correct it.',
              style: AppTextStyles.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashNote extends StatelessWidget {
  final DriverEarningRecord record;

  const _CashNote({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.textSecondary),
          Gap.hSm,
          Expanded(
            child: Text(
              'You collected this one in cash. The ${record.total.formatted} '
              'above is still your earnings — it is counted against the '
              'cash you settle with Zvingo at the end of the shift.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── One day ─────────────────────────────────────────────────────────────────

class _DayBreakdownSheet extends ConsumerWidget {
  final DailySummary summary;

  const _DayBreakdownSheet({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fares = summary.fareEarnings;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              summary.relativeLabel(),
              style: AppTextStyles.onSurface(context, AppTextStyles.h2),
            ),
            Gap.xs,
            Text(
              '${summary.displayDate} · ${summary.tripCount} '
              '${summary.tripCount == 1 ? 'delivery' : 'deliveries'}',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            Gap.xl,
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceMutedOf(context),
                borderRadius: AppSpacing.brLg,
              ),
              child: Column(
                children: [
                  _DayRow(
                    label: 'Delivery fees (your share)',
                    amount: fares,
                  ),
                  Gap.md,
                  _DayRow(label: 'Tips', amount: summary.tips),
                  if (summary.cashCollected.isPositive) ...[
                    Gap.md,
                    _DayRow(
                      label: 'of which collected in cash',
                      amount: summary.cashCollected,
                      muted: true,
                    ),
                  ],
                  Gap.lg,
                  Divider(height: 1, color: AppColors.borderOf(context)),
                  Gap.lg,
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Take-home',
                          style: AppTextStyles.bodyStrong
                              .copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                      Text(
                        summary.earnings.formatted,
                        style: AppTextStyles.moneyLarge.copyWith(
                          color: AppColors.successOf(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (summary.perTrip != null) ...[
              Gap.md,
              Text(
                'That is ${summary.perTrip!.formatted} per delivery on average.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
            Gap.xl,
            DriverPrimaryButton(
              label: 'See these deliveries',
              icon: Icons.receipt_long_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(earningsProvider.notifier).setFilters(
                      startDate: summary.date,
                      endDate: summary.date,
                    );
                context.push('/earnings/history');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final String label;
  final Money amount;
  final bool muted;

  const _DayRow({
    required this.label,
    required this.amount,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.textSecondary : AppColors.textPrimary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: (muted ? AppTextStyles.caption : AppTextStyles.body)
                .copyWith(color: AppColors.textSecondary),
          ),
        ),
        Gap.hMd,
        Text(
          amount.formatted,
          style: AppTextStyles.money.copyWith(color: color),
        ),
      ],
    );
  }
}

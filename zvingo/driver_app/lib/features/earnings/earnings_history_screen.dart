import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_colors.dart';
import '../../providers/earnings_provider.dart';
import '../../models/earning_record.dart';

/// Full delivery history screen with filters and infinite scroll.
class EarningsHistoryScreen extends ConsumerStatefulWidget {
  const EarningsHistoryScreen({super.key});

  @override
  ConsumerState<EarningsHistoryScreen> createState() =>
      _EarningsHistoryScreenState();
}

class _EarningsHistoryScreenState
    extends ConsumerState<EarningsHistoryScreen> {
  final _scrollController = ScrollController();
  final _merchantSearchController = TextEditingController();
  final _areaSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load first page on mount
    Future.microtask(() {
      ref.read(earningsProvider.notifier).loadHistory(reset: true);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(earningsProvider);
      if (!state.isLoadingHistory && state.hasMoreHistory) {
        ref.read(earningsProvider.notifier).loadHistory();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _merchantSearchController.dispose();
    _areaSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final earnings = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery History'),
        actions: [
          if (_hasActiveFilters(earnings))
            TextButton(
              onPressed: () {
                _merchantSearchController.clear();
                _areaSearchController.clear();
                ref.read(earningsProvider.notifier).clearAllFilters();
              },
              child: const Text('Clear All'),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter Bar ───────────────────────────────
          _FilterBar(
            earnings: earnings,
            merchantController: _merchantSearchController,
            areaController: _areaSearchController,
            onFiltersChanged: (filters) {
              ref.read(earningsProvider.notifier).setFilters(
                    startDate: filters['startDate'],
                    clearStartDate: filters['clearStartDate'] == true,
                    endDate: filters['endDate'],
                    clearEndDate: filters['clearEndDate'] == true,
                    paymentMethod: filters['paymentMethod'],
                    clearPaymentMethod:
                        filters['clearPaymentMethod'] == true,
                    minAmountCents: filters['minAmountCents'],
                    clearMinAmount: filters['clearMinAmount'] == true,
                    merchantName: filters['merchantName'],
                    clearMerchantName:
                        filters['clearMerchantName'] == true,
                    area: filters['area'],
                    clearArea: filters['clearArea'] == true,
                  );
            },
          ),

          // ── Results count ────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${earnings.historyTotal} deliveries',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                if (earnings.isLoadingHistory)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          // ── Delivery List ────────────────────────────
          Expanded(
            child: earnings.historyRecords.isEmpty &&
                    !earnings.isLoadingHistory
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 48,
                            color: AppColors.textSecondary
                                .withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'No deliveries found',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                        if (_hasActiveFilters(earnings))
                          TextButton(
                            onPressed: () {
                              _merchantSearchController.clear();
                              _areaSearchController.clear();
                              ref
                                  .read(earningsProvider.notifier)
                                  .clearAllFilters();
                            },
                            child: const Text('Clear filters'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: earnings.historyRecords.length +
                        (earnings.hasMoreHistory ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= earnings.historyRecords.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                              child: CircularProgressIndicator()),
                        );
                      }
                      return _DeliveryCard(
                          record: earnings.historyRecords[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters(EarningsState s) =>
      s.filterStartDate != null ||
      s.filterEndDate != null ||
      s.filterPaymentMethod != null ||
      s.filterMinAmountCents != null ||
      s.filterMerchantName != null ||
      s.filterArea != null;
}

// ── Filter Bar Widget ──────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final EarningsState earnings;
  final TextEditingController merchantController;
  final TextEditingController areaController;
  final void Function(Map<String, dynamic>) onFiltersChanged;

  const _FilterBar({
    required this.earnings,
    required this.merchantController,
    required this.areaController,
    required this.onFiltersChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Date range + Payment method
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Date range
                _FilterChip(
                  label: earnings.filterStartDate != null
                      ? '${earnings.filterStartDate} – ${earnings.filterEndDate ?? 'now'}'
                      : 'Date Range',
                  isActive: earnings.filterStartDate != null,
                  icon: Icons.calendar_today,
                  onTap: () => _pickDateRange(context),
                  onRemove: earnings.filterStartDate != null
                      ? () => onFiltersChanged({
                            'clearStartDate': true,
                            'clearEndDate': true,
                          })
                      : null,
                ),
                const SizedBox(width: 8),

                // Payment method
                _FilterChip(
                  label: earnings.filterPaymentMethod != null
                      ? earnings.filterPaymentMethod!.toUpperCase()
                      : 'Payment',
                  isActive: earnings.filterPaymentMethod != null,
                  icon: Icons.payments_outlined,
                  onTap: () => _pickPaymentMethod(context),
                  onRemove: earnings.filterPaymentMethod != null
                      ? () => onFiltersChanged({
                            'clearPaymentMethod': true,
                          })
                      : null,
                ),
                const SizedBox(width: 8),

                // Min amount
                _FilterChip(
                  label: earnings.filterMinAmountCents != null
                      ? 'Min \$${(earnings.filterMinAmountCents! / 100).toStringAsFixed(0)}'
                      : 'Min Amount',
                  isActive: earnings.filterMinAmountCents != null,
                  icon: Icons.attach_money,
                  onTap: () => _pickMinAmount(context),
                  onRemove: earnings.filterMinAmountCents != null
                      ? () => onFiltersChanged({
                            'clearMinAmount': true,
                          })
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Row 2: Merchant + Area search fields
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: merchantController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Merchant name...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.store, size: 18),
                      suffixIcon: merchantController.text.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                merchantController.clear();
                                onFiltersChanged({
                                  'clearMerchantName': true,
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      if (value.isEmpty) {
                        onFiltersChanged({'clearMerchantName': true});
                      } else {
                        onFiltersChanged({'merchantName': value});
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: areaController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Area/suburb...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon:
                          const Icon(Icons.location_on, size: 18),
                      suffixIcon: areaController.text.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                areaController.clear();
                                onFiltersChanged({'clearArea': true});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      if (value.isEmpty) {
                        onFiltersChanged({'clearArea': true});
                      } else {
                        onFiltersChanged({'area': value});
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: earnings.filterStartDate != null
          ? DateTimeRange(
              start: DateTime.parse(earnings.filterStartDate!),
              end: earnings.filterEndDate != null
                  ? DateTime.parse(earnings.filterEndDate!)
                  : now,
            )
          : null,
    );
    if (range != null) {
      final fmt = (DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      onFiltersChanged({
        'startDate': fmt(range.start),
        'endDate': fmt(range.end),
      });
    }
  }

  Future<void> _pickPaymentMethod(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.money),
              title: const Text('Cash'),
              onTap: () => Navigator.pop(ctx, 'cash'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('EcoCash'),
              onTap: () => Navigator.pop(ctx, 'ecocash'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      onFiltersChanged({'paymentMethod': result});
    }
  }

  Future<void> _pickMinAmount(BuildContext context) async {
    final amounts = [100, 200, 500, 1000, 2000]; // cents
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Minimum Earning',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...amounts.map((a) => ListTile(
                  title: Text('\$${(a / 100).toStringAsFixed(2)}'),
                  onTap: () => Navigator.pop(ctx, a),
                )),
          ],
        ),
      ),
    );
    if (result != null) {
      onFiltersChanged({'minAmountCents': result});
    }
  }
}

// ── Filter Chip ─────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.icon,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isActive ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close,
                    size: 14, color: AppColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Delivery Card ───────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final DriverEarningRecord record;

  const _DeliveryCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: merchant + time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  record.merchantName,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                record.formattedDateTime,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Route: masked addresses
          if (record.routeDescription.isNotEmpty)
            Row(
              children: [
                Icon(Icons.route,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    record.routeDescription,
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),

          // Bottom row: earnings + payment badge + distance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Earnings breakdown
              Row(
                children: [
                  Text(
                    record.formattedEarnings,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                  ),
                  if (record.tipCents > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+${record.formattedTip} tip',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Payment method + distance
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: record.paymentMethod == 'cash'
                          ? Colors.green.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      record.paymentMethod.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: record.paymentMethod == 'cash'
                            ? Colors.green.shade700
                            : Colors.blue.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    record.formattedDistance,
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

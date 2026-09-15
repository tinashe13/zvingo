/// The sections of the checkout screen, kept out of the screen file so the
/// ordering logic there stays readable.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/checkout/order_placement_provider.dart';
import 'package:consumer_app/features/checkout/order_quote.dart';
import 'package:consumer_app/features/checkout/promo_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A tinted, always-explained notice. Never colour alone (§1.5).
class CheckoutNotice extends StatelessWidget {
  const CheckoutNotice({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ZvTone tone;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration:
          BoxDecoration(color: tone.surface, borderRadius: AppRadius.mdAll),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: tone.foreground)),
                const SizedBox(height: 2),
                Text(message,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Where and when ───────────────────────────────────────────────

class FulfilmentSection extends StatelessWidget {
  const FulfilmentSection({
    super.key,
    required this.mode,
    required this.restaurant,
    required this.location,
    required this.scheduledAt,
    required this.instructions,
    required this.instructionOptions,
    required this.onModeChanged,
    required this.onAddressTap,
    required this.onInstructionsChanged,
    required this.onScheduleChanged,
  });

  final FulfilmentMode mode;
  final Restaurant? restaurant;
  final DeliveryLocation? location;
  final DateTime? scheduledAt;
  final String instructions;
  final List<String> instructionOptions;
  final ValueChanged<FulfilmentMode> onModeChanged;
  final VoidCallback onAddressTap;
  final ValueChanged<String> onInstructionsChanged;
  final ValueChanged<DateTime?> onScheduleChanged;

  /// Pre-orders are offered when the merchant takes them at all. While the
  /// restaurant is closed, `availability.acceptsScheduled` is the authority.
  bool get _canSchedule {
    final store = restaurant;
    if (store == null) return true;
    if (store.isOpen) return store.acceptsScheduledOrders;
    return store.availability.acceptsScheduled;
  }

  @override
  Widget build(BuildContext context) {
    final isPickup = mode == FulfilmentMode.pickup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(isPickup ? 'Collection' : 'Delivery', style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.delivery_dining_outlined,
                title: 'Delivery',
                subtitle: restaurant?.deliveryTime ?? 'To your address',
                selected: !isPickup,
                onTap: () => onModeChanged(FulfilmentMode.delivery),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _ModeCard(
                icon: Icons.storefront_outlined,
                title: 'Pickup',
                subtitle: 'No delivery fee',
                selected: isPickup,
                onTap: () => onModeChanged(FulfilmentMode.pickup),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isPickup)
          ZvCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Collect from',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        restaurant?.address.isNotEmpty ?? false
                            ? restaurant!.address
                            : restaurant?.name ?? 'the restaurant',
                        style: AppTextStyles.bodyStrong,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ZvCard(
            onTap: onAddressTap,
            color: location == null
                ? AppColors.warningSurface
                : AppColors.surface,
            borderColor:
                location == null ? AppColors.warning : AppColors.border,
            child: Row(
              children: [
                Icon(
                  location == null
                      ? Icons.wrong_location_outlined
                      : Icons.place_outlined,
                  size: 20,
                  color: location == null
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location == null
                            ? 'No delivery address'
                            : 'Delivering to',
                        style: AppTextStyles.caption.copyWith(
                          color: location == null
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        location?.displayName ??
                            'Tap to choose where this goes',
                        style: AppTextStyles.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        if (!isPickup) ...[
          const SizedBox(height: AppSpacing.xs),
          ZvCard(
            onTap: () => _pickInstructions(context),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dropoff instructions',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(instructions, style: AppTextStyles.bodyStrong),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        ZvCard(
          onTap: _canSchedule ? () => _pickSlot(context) : null,
          child: Row(
            children: [
              Icon(
                scheduledAt == null
                    ? Icons.bolt_rounded
                    : Icons.event_available_rounded,
                size: 20,
                color: scheduledAt == null
                    ? AppColors.brandGreen
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('When',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      scheduledAt == null
                          ? 'As soon as possible'
                          : _slotLabel(scheduledAt!),
                      style: AppTextStyles.bodyStrong,
                    ),
                  ],
                ),
              ),
              if (!_canSchedule)
                Text('Not available here',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary))
              else
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ],
    );
  }

  void _pickInstructions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => ZvSheet(
        title: 'Dropoff instructions',
        subtitle: 'The driver sees this when they arrive',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in instructionOptions)
              ListTile(
                minVerticalPadding: AppSpacing.sm,
                leading: Icon(
                  option == instructions
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: option == instructions
                      ? AppColors.actionDefault
                      : AppColors.neutral400,
                ),
                title: Text(option, style: AppTextStyles.body),
                onTap: () {
                  onInstructionsChanged(option);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  void _pickSlot(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => _SchedulePickerSheet(
        selected: scheduledAt,
        onPicked: (value) {
          onScheduleChanged(value);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  static String _slotLabel(DateTime slot) {
    final local = slot.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return isToday ? 'Today at $hh:$mm' : '${local.day}/${local.month} at $hh:$mm';
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      onTap: onTap,
      color: selected ? AppColors.surfaceMuted : AppColors.surface,
      borderColor: selected ? AppColors.actionDefault : AppColors.border,
      padding: const EdgeInsets.all(AppSpacing.sm),
      semanticLabel: '$title, $subtitle',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected
                      ? AppColors.actionDefault
                      : AppColors.textSecondary),
              const Spacer(),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppColors.actionDefault),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: AppTextStyles.bodyStrong),
          Text(subtitle,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Slots on the half hour for the next two days, skipping anything less than
/// 45 minutes away (the kitchen needs a runway).
class _SchedulePickerSheet extends StatelessWidget {
  const _SchedulePickerSheet({required this.selected, required this.onPicked});

  final DateTime? selected;
  final ValueChanged<DateTime?> onPicked;

  @override
  Widget build(BuildContext context) {
    final slots = _slots();
    return ZvSheet(
      title: 'Choose a time',
      subtitle: 'We start your order so it is ready for the slot you pick',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          children: [
            ZvCard(
              onTap: () => onPicked(null),
              color: selected == null
                  ? AppColors.surfaceMuted
                  : AppColors.surface,
              borderColor: selected == null
                  ? AppColors.actionDefault
                  : AppColors.border,
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded,
                      size: 20, color: AppColors.brandGreen),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('As soon as possible',
                            style: AppTextStyles.bodyStrong),
                        Text('We dispatch a driver straight away',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (selected == null)
                    const Icon(Icons.check_circle_rounded,
                        size: 20, color: AppColors.actionDefault),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final day in _groupByDay(slots).entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(day.key, style: AppTextStyles.h3),
              ),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final slot in day.value)
                    _SlotChip(
                      label: _time(slot),
                      selected: selected != null &&
                          selected!.isAtSameMomentAs(slot),
                      onTap: () => onPicked(slot),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  static List<DateTime> _slots() {
    final now = DateTime.now();
    final first = now.add(const Duration(minutes: 45));
    var cursor = DateTime(now.year, now.month, now.day, now.hour, 0)
        .add(const Duration(minutes: 30));
    final result = <DateTime>[];
    final end = now.add(const Duration(days: 2));
    while (cursor.isBefore(end)) {
      if (cursor.isAfter(first) && cursor.hour >= 7 && cursor.hour <= 21) {
        result.add(cursor);
      }
      cursor = cursor.add(const Duration(minutes: 30));
    }
    return result;
  }

  static Map<String, List<DateTime>> _groupByDay(List<DateTime> slots) {
    final now = DateTime.now();
    final grouped = <String, List<DateTime>>{};
    for (final slot in slots) {
      final isToday = slot.year == now.year &&
          slot.month == now.month &&
          slot.day == now.day;
      final isTomorrow = slot.difference(DateTime(now.year, now.month, now.day))
              .inDays ==
          1;
      final key = isToday
          ? 'Today'
          : isTomorrow
              ? 'Tomorrow'
              : '${slot.day}/${slot.month}';
      grouped.putIfAbsent(key, () => <DateTime>[]).add(slot);
    }
    return grouped;
  }

  static String _time(DateTime slot) =>
      '${slot.hour.toString().padLeft(2, '0')}:'
      '${slot.minute.toString().padLeft(2, '0')}';
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Deliver at $label',
      child: Container(
        constraints: const BoxConstraints(
            minHeight: AppSpacing.minTapTarget, minWidth: 76),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.actionDefault : AppColors.surfaceMuted,
          borderRadius: AppRadius.fullAll,
        ),
        child: Text(
          label,
          style: AppTextStyles.money.copyWith(
            color: selected ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Items ────────────────────────────────────────────────────────

class OrderItemsSection extends StatelessWidget {
  const OrderItemsSection({
    super.key,
    required this.items,
    required this.restaurantName,
    required this.onEditCart,
  });

  final List<CartItem> items;
  final String? restaurantName;
  final VoidCallback onEditCart;

  @override
  Widget build(BuildContext context) {
    final units = items.fold(0, (sum, item) => sum + item.quantity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Your order · $units item${units == 1 ? '' : 's'}',
                style: AppTextStyles.h2,
              ),
            ),
            ZvButton.tertiary(
              label: 'Edit',
              icon: Icons.edit_outlined,
              onPressed: onEditCart,
            ),
          ],
        ),
        if (restaurantName != null) ...[
          const SizedBox(height: 2),
          Text(restaurantName!,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),
        ],
        const SizedBox(height: AppSpacing.sm),
        ZvCard(
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: AppSpacing.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${items[i].quantity}×',
                          style: AppTextStyles.money),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].name, style: AppTextStyles.body),
                          if (items[i].choices.isNotEmpty)
                            Text(items[i].choicesSummary,
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textSecondary)),
                          if ((items[i].specialInstructions ?? '').isNotEmpty)
                            Text('Note: ${items[i].specialInstructions}',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(items[i].lineTotal.format(),
                        style: AppTextStyles.money),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Promo ────────────────────────────────────────────────────────

class PromoSection extends StatelessWidget {
  const PromoSection({
    super.key,
    required this.controller,
    required this.state,
    required this.onApply,
    required this.onRemove,
  });

  final TextEditingController controller;
  final PromoState state;
  final Future<void> Function() onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (state.isApplied) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Promo code', style: AppTextStyles.h2),
          const SizedBox(height: AppSpacing.sm),
          ZvCard(
            color: AppColors.successSurface,
            borderColor: AppColors.success,
            child: Row(
              children: [
                const Icon(Icons.verified_rounded,
                    size: 20, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(state.code ?? '',
                          style: AppTextStyles.bodyStrong),
                      if (state.message != null)
                        Text(state.message!,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                ZvIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Remove promo code',
                  background: Colors.transparent,
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Promo code', style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ZvTextField(
                label: 'Have a code?',
                optionalLabel: true,
                hint: 'ZVINGO10',
                controller: controller,
                errorText: state.isRejected ? state.message : null,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onApply(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-_]')),
                  LengthLimitingTextInputFormatter(24),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Padding(
              // Line the button up with the field, not with its label.
              padding: const EdgeInsets.only(top: 26),
              child: ZvButton.secondary(
                label: 'Apply',
                fullWidth: false,
                loading: state.isBusy,
                onPressed: state.isBusy ? null : () => onApply(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Tip ──────────────────────────────────────────────────────────

class TipSection extends StatelessWidget {
  const TipSection({
    super.key,
    required this.currency,
    required this.selectedIndex,
    required this.customTip,
    required this.onPresetSelected,
    required this.onCustomTip,
  });

  final String currency;
  final int selectedIndex;
  final Money? customTip;
  final ValueChanged<int> onPresetSelected;
  final Future<void> Function(String currency) onCustomTip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Driver tip', style: AppTextStyles.h2),
        const SizedBox(height: 2),
        Text(
          '100% of the tip goes to your driver, on top of their delivery share.',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var i = 0; i < kTipPresets.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _TipChip(
                  label: kTipPresets[i].cents == 0
                      ? 'None'
                      : kTipPresets[i].money(currency).format(),
                  selected: selectedIndex == i,
                  onTap: () => onPresetSelected(i),
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _TipChip(
                label: customTip?.format() ?? 'Other',
                selected: customTip != null,
                onTap: () => onCustomTip(currency),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Tip $label',
      child: AnimatedContainer(
        duration: context.motion(AppMotion.fast),
        curve: context.motionCurve(AppMotion.standard),
        height: AppSpacing.minTapTarget,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: selected ? AppColors.actionDefault : AppColors.surfaceMuted,
          borderRadius: AppRadius.fullAll,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: AppTextStyles.button.copyWith(
              color: selected ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom tip entry. Validates before it can be applied, so a typo cannot turn
/// into a charge.
class CustomTipSheet extends StatefulWidget {
  const CustomTipSheet({
    super.key,
    required this.controller,
    required this.currency,
  });

  final TextEditingController controller;
  final String currency;

  @override
  State<CustomTipSheet> createState() => _CustomTipSheetState();
}

class _CustomTipSheetState extends State<CustomTipSheet> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final spec = currencySpec(widget.currency);
    return ZvSheet(
      title: 'Custom tip',
      subtitle: 'Goes straight to your driver',
      footer: ZvButton.primary(
        label: 'Apply tip',
        onPressed: _apply,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: ZvTextField(
          label: 'Amount (${spec.code})',
          hint: '0.00',
          controller: widget.controller,
          errorText: _error,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            LengthLimitingTextInputFormatter(7),
          ],
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _apply(),
          helper: 'Anything from ${spec.symbol}0.00 upwards.',
        ),
      ),
    );
  }

  void _apply() {
    final parsed =
        Money.tryParse(widget.controller.text, currency: widget.currency);
    if (parsed == null) {
      setState(() => _error = 'Enter an amount like 2.50.');
      return;
    }
    if (parsed.minor > 10000) {
      setState(() => _error = 'That is a very large tip — '
          'the most you can add here is ${currencySpec(widget.currency).symbol}100.00.');
      return;
    }
    Navigator.of(context).pop(parsed);
  }
}

// ── Price breakdown ──────────────────────────────────────────────

class PriceBreakdownSection extends StatelessWidget {
  const PriceBreakdownSection({
    super.key,
    required this.quote,
    required this.promo,
  });

  final OrderQuote quote;
  final PromoState promo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('What you pay', style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.sm),
        ZvCard(
          child: Column(
            children: [
              _Row(label: 'Food subtotal', amount: quote.subtotal),
              const SizedBox(height: AppSpacing.sm),
              _Row(
                label: quote.isPickup ? 'Delivery (pickup)' : 'Delivery fee',
                amount: quote.deliveryFee,
                zeroLabel: quote.isPickup
                    ? 'Not charged'
                    : (quote.freeDeliveryFromPromo ? 'Free' : 'Free'),
                note: quote.isPickup
                    ? 'You are collecting this order yourself.'
                    : quote.freeDeliveryFromPromo
                        ? 'Waived by your promo code.'
                        : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              _Row(
                label: 'Service fee',
                amount: quote.serviceFee,
                note: 'Keeps Zvingo running — support, payments and dispatch.',
              ),
              if (quote.tax.isPositive) ...[
                const SizedBox(height: AppSpacing.sm),
                _Row(label: 'Tax', amount: quote.tax),
              ],
              if (quote.hasDiscount) ...[
                const SizedBox(height: AppSpacing.sm),
                _Row(
                  label: 'Promo ${promo.code ?? ''}'.trim(),
                  amount: -quote.discount,
                  tint: AppColors.success,
                ),
              ],
              if (quote.tip.isPositive) ...[
                const SizedBox(height: AppSpacing.sm),
                _Row(label: 'Driver tip', amount: quote.tip),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  const Text('Total', style: AppTextStyles.h3),
                  const Spacer(),
                  ZvAnimatedCount.money(
                    value: quote.total.major,
                    currency: quote.total.symbol,
                    style: AppTextStyles.moneyLarge,
                    semanticLabel: 'Total to pay',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.amount,
    this.zeroLabel,
    this.note,
    this.tint,
  });

  final String label;
  final Money amount;
  final String? zeroLabel;
  final String? note;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary)),
            ),
            Text(
              amount.isZero && zeroLabel != null
                  ? zeroLabel!
                  : amount.format(showSign: amount.isNegative),
              style: AppTextStyles.money
                  .copyWith(color: tint ?? AppColors.textPrimary),
            ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note!,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textTertiary)),
        ],
      ],
    );
  }
}

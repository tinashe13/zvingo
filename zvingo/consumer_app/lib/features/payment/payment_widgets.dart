/// Payment UI shared by the checkout screen and the standalone payment screen,
/// so the two can never drift apart in what they promise the customer.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/payment/payment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The four rails Zvingo actually supports. Card is intentionally absent —
/// see the header comment in `payment_provider.dart`.
const List<PaymentMethodType> kOfferedPaymentMethods = <PaymentMethodType>[
  PaymentMethodType.ecocash,
  PaymentMethodType.onemoney,
  PaymentMethodType.innbucks,
  PaymentMethodType.cash,
];

class PaymentMethodPicker extends StatelessWidget {
  const PaymentMethodPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.allowCash = true,
    this.methods = kOfferedPaymentMethods,
  });

  final PaymentMethodType selected;
  final ValueChanged<PaymentMethodType> onSelected;

  /// Cash makes no sense on a retry screen for an order already placed.
  final bool allowCash;
  final List<PaymentMethodType> methods;

  @override
  Widget build(BuildContext context) {
    final visible = methods
        .where((m) => allowCash || m != PaymentMethodType.cash)
        .toList();
    return Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _MethodTile(
            method: visible[i],
            isSelected: visible[i] == selected,
            onTap: () => onSelected(visible[i]),
          ),
        ],
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  final PaymentMethodType method;
  final bool isSelected;
  final VoidCallback onTap;

  static const Map<PaymentMethodType, String> _assets = {
    PaymentMethodType.ecocash: 'assets/images/ecocash.png',
    PaymentMethodType.onemoney: 'assets/images/onemoney.png',
    PaymentMethodType.innbucks: 'assets/images/innbucks.png',
    PaymentMethodType.cash: 'assets/images/cash.png',
  };

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      onTap: onTap,
      color: isSelected ? AppColors.surfaceMuted : AppColors.surface,
      borderColor: isSelected ? AppColors.actionDefault : AppColors.border,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      semanticLabel: '${method.label}. ${method.blurb}',
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 32,
            child: Image.asset(
              _assets[method]!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                method == PaymentMethodType.cash
                    ? Icons.payments_outlined
                    : Icons.smartphone_rounded,
                size: 24,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(method.label, style: AppTextStyles.bodyStrong),
                const SizedBox(height: 2),
                Text(method.blurb,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 22,
            color:
                isSelected ? AppColors.actionDefault : AppColors.neutral400,
          ),
        ],
      ),
    );
  }
}

/// The phone number the debit goes to. Validated before anything is charged.
class MobileMoneyPhoneField extends StatelessWidget {
  const MobileMoneyPhoneField({
    super.key,
    required this.controller,
    required this.method,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final PaymentMethodType method;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ZvTextField(
      label: '${method.label} number',
      hint: '077 123 4567',
      controller: controller,
      errorText: errorText,
      onChanged: onChanged,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      prefixIcon: Icons.smartphone_rounded,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
        LengthLimitingTextInputFormatter(16),
      ],
      helper: 'The prompt goes to this number. '
          'Zimbabwe numbers only (+263).',
    );
  }
}

/// What the customer sees while the prompt is sitting on their phone.
class PaymentWaitingPanel extends StatelessWidget {
  const PaymentWaitingPanel({
    super.key,
    required this.session,
    required this.onCancel,
  });

  final PaymentSession session;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final method = session.method ?? PaymentMethodType.ecocash;
    final seconds = session.secondsRemaining;
    final progress = seconds == null
        ? null
        : (1 - seconds / kPaymentWindow.inSeconds).clamp(0.0, 1.0);

    return ZvCard(
      color: AppColors.warningSurface,
      borderColor: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phonelink_ring_rounded,
                  size: 20, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Check your phone now',
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.warning),
                ),
              ),
              if (seconds != null)
                Text(
                  _clock(seconds),
                  style: AppTextStyles.time.copyWith(color: AppColors.warning),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(method.waitingInstruction, style: AppTextStyles.body),
          if (session.amount != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'You are approving ${session.amount!.format()}. '
              'Nothing leaves your wallet until you enter your PIN.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadius.fullAll,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: AppColors.neutral200,
                color: AppColors.warning,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: ZvButton.tertiary(
              label: 'I cannot approve it right now',
              onPressed: onCancel,
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// A failed payment, with the reason and a way forward.
class PaymentFailurePanel extends StatelessWidget {
  const PaymentFailurePanel({
    super.key,
    required this.reason,
    required this.onRetry,
    this.onSecondary,
    this.secondaryLabel,
  });

  final String reason;
  final VoidCallback onRetry;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      color: AppColors.errorSurface,
      borderColor: AppColors.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 20, color: AppColors.error),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text('Payment did not go through',
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: AppColors.error)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(reason, style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ZvButton.primary(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ),
              if (onSecondary != null && secondaryLabel != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: ZvButton.secondary(
                    label: secondaryLabel!,
                    onPressed: onSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Settlement-currency picker. Prices are quoted in USD; Paynow can settle in
/// ZIG or ZAR at the backend's pinned rate.
class SettlementCurrencyPicker extends StatelessWidget {
  const SettlementCurrencyPicker({
    super.key,
    required this.selected,
    required this.rates,
    required this.usdAmount,
    required this.onSelected,
  });

  final String selected;
  final Map<String, double> rates;
  final Money usdAmount;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final available = kCurrencies.keys
        .where((code) => code == 'USD' || rates.containsKey(code))
        .toList();
    if (available.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pay in', style: AppTextStyles.h3),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final code in available)
              _CurrencyChip(
                code: code,
                label: _amountIn(code).format(),
                selected: code == selected,
                onTap: () => onSelected(code),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          selected == 'USD'
              ? 'Charged in US dollars.'
              : 'Converted at today\'s Zvingo rate, pinned when you pay.',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Money _amountIn(String code) {
    if (code == 'USD') return usdAmount;
    final rate = rates[code];
    if (rate == null) return usdAmount;
    return usdAmount.convertTo(code, rate);
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Pay in $code, $label',
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? AppColors.actionDefault : AppColors.surfaceMuted,
          borderRadius: AppRadius.fullAll,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              code,
              style: AppTextStyles.overline.copyWith(
                color: selected
                    ? AppColors.textOnDark
                    : AppColors.textSecondary,
              ),
            ),
            Text(
              label,
              style: AppTextStyles.money.copyWith(
                color:
                    selected ? AppColors.textOnDark : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

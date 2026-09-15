/// Standalone payment — reached when an order exists but is not paid for
/// (a failed prompt, a dropped connection, "pay another way" from checkout).
///
/// It answers three questions at every moment: what am I paying, how, and what
/// do I do next on my phone. Nothing on this screen is a dead end — a failure
/// always has the reason plus a retry, and a success hands off to tracking.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/payment/payment_provider.dart';
import 'package:consumer_app/features/payment/payment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final String orderId;

  /// Amount due, in USD major units, passed on the route.
  final double amount;

  const PaymentScreen({super.key, required this.orderId, required this.amount});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _phoneController = TextEditingController();
  PaymentMethodType _method = PaymentMethodType.ecocash;
  String _currency = kDefaultCurrency;
  String? _phoneError;
  bool _celebrated = false;

  Money get _usdDue => Money.fromMajor(widget.amount);

  @override
  void initState() {
    super.initState();
    // Re-attach to an in-flight prompt if one already exists for this order.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(paymentProvider.notifier).refreshForOrder(widget.orderId);
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Money get _amountToCharge {
    if (_currency == kDefaultCurrency) return _usdDue;
    final rates = ref.read(exchangeRatesProvider).valueOrNull;
    final rate = rates?[_currency];
    if (rate == null) return _usdDue;
    return _usdDue.convertTo(_currency, rate);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(paymentProvider);

    ref.listen<PaymentSession>(paymentProvider, (previous, next) {
      if (next.phase == PaymentPhase.paid && !_celebrated && mounted) {
        _celebrated = true;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
            content: Text('Payment confirmed — thank you!'),
          ));
        context.go('/order/${widget.orderId}');
      }
    });

    final waiting = session.phase == PaymentPhase.awaitingCustomer;
    final busy = session.phase == PaymentPhase.initiating;

    return ZvScreen(
      title: 'Payment',
      subtitle: 'Order ${_shortReference(widget.orderId)}',
      fallbackRoute: '/orders',
      footer: ZvStickyFooter(
        child: ZvButton.primary(
          label: 'Pay ${_amountToCharge.format()} with ${_method.label}',
          loading: busy,
          onPressed: waiting || busy ? null : _pay,
          disabledReason: waiting
              ? 'Approve the prompt on your phone, or cancel it below to '
                  'start again.'
              : null,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          ZvCard(
            color: AppColors.background,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amount due',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        _currency == kDefaultCurrency
                            ? 'Charged in US dollars'
                            : 'Converted from ${_usdDue.format()}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                ZvAnimatedCount.money(
                  value: _amountToCharge.major,
                  currency: _amountToCharge.symbol,
                  style: AppTextStyles.moneyDisplay,
                  semanticLabel: 'Amount due',
                ),
              ],
            ),
          ),
          if (waiting) ...[
            const SizedBox(height: AppSpacing.md),
            PaymentWaitingPanel(
              session: session,
              onCancel: () =>
                  ref.read(paymentProvider.notifier).cancelWaiting(),
            ),
          ],
          if (session.phase == PaymentPhase.failed &&
              session.failureReason != null) ...[
            const SizedBox(height: AppSpacing.md),
            PaymentFailurePanel(
              reason: session.failureReason!,
              onRetry: _pay,
              secondaryLabel: 'See my order',
              onSecondary: () => context.go('/order/${widget.orderId}'),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          const Text('How would you like to pay?', style: AppTextStyles.h2),
          const SizedBox(height: AppSpacing.sm),
          PaymentMethodPicker(
            selected: _method,
            allowCash: false,
            onSelected: (value) => setState(() {
              _method = value;
              _phoneError = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          MobileMoneyPhoneField(
            controller: _phoneController,
            method: _method,
            errorText: _phoneError,
            onChanged: (_) {
              if (_phoneError != null) setState(() => _phoneError = null);
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _currencyPicker(),
          const SizedBox(height: AppSpacing.xl),
          ZvCard(
            color: AppColors.infoSurface,
            borderColor: AppColors.info,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 20, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cards are not supported yet',
                          style: AppTextStyles.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        'Zvingo settles through Paynow, which handles EcoCash, '
                        'OneMoney and InnBucks. Card acceptance is not live, so '
                        'we do not offer it rather than take you down a path '
                        'that cannot complete.',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _currencyPicker() {
    final ratesAsync = ref.watch(exchangeRatesProvider);
    return ratesAsync.maybeWhen(
      data: (rates) => SettlementCurrencyPicker(
        selected: _currency,
        rates: rates,
        usdAmount: _usdDue,
        onSelected: (code) => setState(() => _currency = code),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }

  Future<void> _pay() async {
    final error = Payment.validatePhone(_phoneController.text);
    if (error != null) {
      setState(() => _phoneError = error);
      return;
    }
    await ref.read(paymentProvider.notifier).initiatePayment(
          orderId: widget.orderId,
          method: _method,
          phone: _phoneController.text,
          currency: _currency,
          amount: _amountToCharge,
        );
  }

  static String _shortReference(String orderId) {
    final trimmed = orderId.trim();
    if (trimmed.length <= 6) return trimmed.toUpperCase();
    return trimmed.substring(trimmed.length - 6).toUpperCase();
  }
}

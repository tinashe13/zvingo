import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/account/payment_preferences_provider.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/auth/phone_number.dart';
import 'package:consumer_app/features/auth/widgets/phone_field.dart';

/// Payment preferences.
///
/// **Deliberately not a card wallet.** Zvingo settles through Paynow Zimbabwe,
/// which charges a mobile-money wallet by phone number
/// (`POST /payment/initiate` takes `method` + `phone`). There is no card
/// processing in `app/payment/service.py` and nothing anywhere stores a card,
/// so a "saved cards" screen would be a lie with an Add button that could not
/// work. What is real is *which wallet* and *which number* — and pre-filling
/// those is the entire saving at checkout.
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  MobileWallet? _wallet;
  bool _useAccountNumber = true;
  bool _initialised = false;
  bool _saving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _seed(PaymentPreferences prefs) {
    if (_initialised) return;
    _initialised = true;
    _wallet = prefs.wallet;
    _useAccountNumber = prefs.billingPhone == null;
    if (prefs.billingPhone != null) {
      _phoneController.text = ZvPhone.formatNational(prefs.billingPhone!);
    }
  }

  Future<void> _save(String accountPhone) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_useAccountNumber && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _saving = true);
    final billingPhone =
        _useAccountNumber ? null : ZvPhone.toE164(_phoneController.text);
    await ref
        .read(paymentPreferencesStoreProvider.notifier)
        .save(wallet: _wallet, billingPhone: billingPhone);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _wallet == null
              ? 'Cleared — checkout will ask you each time.'
              : 'Checkout will start with ${_wallet!.label}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(paymentPreferencesStoreProvider);
    final profile = ref.watch(userProfileProvider);
    _seed(prefs);

    final accountPhone = profile.valueOrNull?.phone ?? '';

    return ZvScreen(
      title: 'Payment preferences',
      fallbackRoute: '/account',
      footer: ZvStickyFooter(
        child: ZvButton.primary(
          label: 'Save preferences',
          loading: _saving,
          onPressed: _saving ? null : () => _save(accountPhone),
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            const _HowPaymentWorksCard(),
            const SizedBox(height: AppSpacing.xl),
            const ZvSectionHeader(
              title: 'Preferred wallet',
              subtitle: 'Checkout starts here. You can still change it on the '
                  'day.',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...MobileWallet.values.map(
              (wallet) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _WalletOption(
                  wallet: wallet,
                  selected: _wallet == wallet,
                  onTap: () => setState(
                    () => _wallet = _wallet == wallet ? null : wallet,
                  ),
                ),
              ),
            ),
            if (_wallet == null)
              Text(
                'No wallet chosen — checkout will ask you every time. Tap one '
                'above to make it the default.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            const SizedBox(height: AppSpacing.xl),
            const ZvSectionHeader(
              title: 'Number to charge',
              subtitle: 'Paynow sends the payment prompt to this number.',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ChoiceRow(
              icon: Icons.person_outline_rounded,
              title: 'My account number',
              subtitle: accountPhone.isEmpty
                  ? 'The number you signed up with'
                  : ZvPhone.formatDisplay(accountPhone),
              tabularSubtitle: accountPhone.isNotEmpty,
              selected: _useAccountNumber,
              onTap: () => setState(() => _useAccountNumber = true),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ChoiceRow(
              icon: Icons.group_outlined,
              title: 'A different number',
              subtitle: 'Paying with someone else\'s wallet, or a second line',
              selected: !_useAccountNumber,
              onTap: () => setState(() => _useAccountNumber = false),
            ),
            if (!_useAccountNumber) ...[
              const SizedBox(height: AppSpacing.sm),
              ZvPhoneField(
                controller: _phoneController,
                label: 'Wallet number',
                helper:
                    'The wallet holder approves the payment on their phone.',
                validator: ZvPhone.validate,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (!prefs.isEmpty)
              ZvButton.secondary(
                label: 'Clear saved preference',
                icon: Icons.backspace_outlined,
                onPressed: _saving
                    ? null
                    : () async {
                        await ref
                            .read(paymentPreferencesStoreProvider.notifier)
                            .clear();
                        if (!context.mounted) return;
                        setState(() {
                          _wallet = null;
                          _useAccountNumber = true;
                          _phoneController.clear();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Payment preference cleared'),
                          ),
                        );
                      },
              ),
          ],
        ),
      ),
    );
  }
}

/// States plainly what Zvingo does and does not hold, so nobody goes looking
/// for a card screen that does not and should not exist.
class _HowPaymentWorksCard extends StatelessWidget {
  const _HowPaymentWorksCard();

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      color: AppColors.brandGreenSurface,
      borderColor: AppColors.brandGreenSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: AppColors.brandGreen),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Zvingo never stores your money details',
                  style: AppTextStyles.h3
                      .copyWith(color: AppColors.brandGreenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'You pay with EcoCash, OneMoney or InnBucks. When you place an '
            'order, Paynow sends a prompt to your phone and you approve it '
            'there with your own PIN. No card numbers and no PINs are ever '
            'typed into, or kept by, this app.',
            style:
                AppTextStyles.caption.copyWith(color: AppColors.brandGreenDark),
          ),
        ],
      ),
    );
  }
}

class _WalletOption extends StatelessWidget {
  const _WalletOption({
    required this.wallet,
    required this.selected,
    required this.onTap,
  });

  final MobileWallet wallet;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderColor: selected ? AppColors.actionDefault : AppColors.border,
      semanticLabel:
          '${wallet.label}, ${wallet.hint}${selected ? ', selected' : ''}',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  selected ? AppColors.actionDefault : AppColors.surfaceMuted,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(
              wallet.icon,
              size: 22,
              color: selected ? AppColors.textOnDark : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(wallet.label, style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  wallet.hint,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.success : AppColors.neutral300,
          ),
        ],
      ),
    );
  }
}

/// A radio-style row that keeps the design system's card idiom instead of
/// Material's `RadioListTile`.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.tabularSubtitle = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool tabularSubtitle;

  @override
  Widget build(BuildContext context) {
    final subtitleStyle = tabularSubtitle
        ? AppTextStyles.tabular(AppTextStyles.caption)
        : AppTextStyles.caption;

    return ZvCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderColor: selected ? AppColors.actionDefault : AppColors.border,
      semanticLabel: '$title${selected ? ', selected' : ''}',
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyStrong),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  subtitle,
                  style: subtitleStyle.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.actionDefault : AppColors.neutral300,
          ),
        ],
      ),
    );
  }
}

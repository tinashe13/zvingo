import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/common/zvingo_ui.dart';

part 'payment_preferences_provider.g.dart';

/// The mobile-money wallets Zvingo can actually charge.
///
/// These are exactly the values `PaymentMethod` accepts in
/// `backend/app/payment/schemas.py`, minus `CARD`: the enum carries a `CARD`
/// member but nothing in `app/payment/service.py` implements it and checkout
/// still says card payments are unavailable. This app therefore does not offer
/// card management at all — see [PaymentPreferences].
enum MobileWallet {
  ecocash('ECOCASH', 'EcoCash', 'Econet · 077, 078'),
  onemoney('ONEMONEY', 'OneMoney', 'NetOne · 071'),
  innbucks('INNBUCKS', 'InnBucks', 'Any network');

  const MobileWallet(this.apiValue, this.label, this.hint);

  /// The string sent as `method` to `POST /payment/initiate`.
  final String apiValue;
  final String label;

  /// Which network the wallet belongs to, so people pick the right one.
  final String hint;

  IconData get icon => switch (this) {
        MobileWallet.ecocash => Icons.phone_android_rounded,
        MobileWallet.onemoney => Icons.account_balance_wallet_outlined,
        MobileWallet.innbucks => Icons.savings_outlined,
      };

  static MobileWallet? fromApiValue(String? value) {
    if (value == null) return null;
    for (final wallet in MobileWallet.values) {
      if (wallet.apiValue == value) return wallet;
    }
    return null;
  }
}

/// How this customer prefers to pay.
class PaymentPreferences {
  const PaymentPreferences({this.wallet, this.billingPhone});

  /// The wallet checkout should pre-select. `null` means "ask me each time".
  final MobileWallet? wallet;

  /// The E.164 number the wallet is registered to. `null` means "use the
  /// number on my account".
  final String? billingPhone;

  bool get isEmpty => wallet == null && billingPhone == null;

  PaymentPreferences copyWith({
    MobileWallet? wallet,
    String? billingPhone,
    bool clearWallet = false,
    bool clearPhone = false,
  }) {
    return PaymentPreferences(
      wallet: clearWallet ? null : (wallet ?? this.wallet),
      billingPhone: clearPhone ? null : (billingPhone ?? this.billingPhone),
    );
  }
}

/// Stores the payment preference **on this device**.
///
/// There is no server field for it: `User` in `backend/app/auth/models.py` has
/// no `preferred_payment_method` or `billing_phone`, and `PATCH /auth/me`
/// accepts only `full_name` and `email`. So this is a local convenience, and
/// the screen says so rather than implying it follows the account around.
/// Making it sync is a small backend change — it is written up in the C4
/// report.
///
/// Nothing sensitive is kept here: a mobile-money wallet choice and a phone
/// number the user already gives the driver. No PIN, no card, no token.
@Riverpod(keepAlive: true)
class PaymentPreferencesStore extends _$PaymentPreferencesStore {
  static const String _boxName = 'settings';
  static const String _walletKey = 'preferred_wallet';
  static const String _phoneKey = 'billing_phone';

  Box get _box => Hive.box(_boxName);

  @override
  PaymentPreferences build() {
    try {
      final phone = _box.get(_phoneKey)?.toString();
      return PaymentPreferences(
        wallet: MobileWallet.fromApiValue(_box.get(_walletKey)?.toString()),
        billingPhone: (phone == null || phone.isEmpty) ? null : phone,
      );
    } catch (_) {
      return const PaymentPreferences();
    }
  }

  Future<void> save({MobileWallet? wallet, String? billingPhone}) async {
    if (wallet == null) {
      await _box.delete(_walletKey);
    } else {
      await _box.put(_walletKey, wallet.apiValue);
    }
    if (billingPhone == null || billingPhone.isEmpty) {
      await _box.delete(_phoneKey);
    } else {
      await _box.put(_phoneKey, billingPhone);
    }
    state = PaymentPreferences(wallet: wallet, billingPhone: billingPhone);
  }

  Future<void> clear() async {
    await _box.delete(_walletKey);
    await _box.delete(_phoneKey);
    state = const PaymentPreferences();
  }
}

/// Small helper so other surfaces can show the saved wallet consistently.
extension PaymentPreferencesSummary on PaymentPreferences {
  String summary(String accountPhone) {
    if (wallet == null) {
      return 'Not set — you will pick a wallet at checkout';
    }
    final number = billingPhone ?? accountPhone;
    return '${wallet!.label} · ${_pretty(number)}';
  }

  static String _pretty(String raw) => raw.isEmpty ? 'your account number' : raw;
}

/// A tone-consistent chip for the wallet, reused on the account screen.
class WalletChip extends StatelessWidget {
  const WalletChip({super.key, required this.wallet});

  final MobileWallet wallet;

  @override
  Widget build(BuildContext context) {
    return ZvStatusChip(
      label: wallet.label,
      tone: ZvTone.brand,
      icon: wallet.icon,
      compact: true,
      uppercase: false,
    );
  }
}

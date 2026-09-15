/// Mobile-money payment state machine.
///
/// The real Zimbabwe path is Paynow: EcoCash, OneMoney and InnBucks. The app
/// asks the backend to initiate, then the customer approves the debit **on
/// their own phone** (a USSD prompt, or the InnBucks app), and Paynow tells the
/// backend. So the app's job between those two moments is to explain what the
/// customer should be doing and to poll `/payment/status/{id}` until the
/// backend says PAID or the prompt expires.
///
/// Card is deliberately absent from [PaymentMethodType]. The backend's
/// `PaymentMethod` enum has a `CARD` member, but `METHOD_PROVIDER_MAP` in
/// `app/payment/service.py` has no entry for it and falls back to `"ecocash"` —
/// so a "card" payment would silently be pushed to EcoCash. Rather than ship a
/// flow that charges the wrong rail, the app does not offer card at all. See
/// the C2 report for the exact backend work that would unlock it.
library;

import 'dart:async';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'payment_provider.g.dart';

/// Payment rails the app offers. Every one of these is implemented end to end.
enum PaymentMethodType {
  /// Paynow — EcoCash mobile money (Econet).
  ecocash,

  /// Paynow — OneMoney mobile wallet (NetOne).
  onemoney,

  /// Paynow — InnBucks wallet.
  innbucks,

  /// Pay the driver on arrival. No online payment is initiated.
  cash,
}

extension PaymentMethodDisplay on PaymentMethodType {
  /// Wire value for `PaymentInitiate.method`. Cash never reaches the API — the
  /// backend enum has no CASH member, so [requiresOnlinePayment] gates it.
  String get wireValue => switch (this) {
        PaymentMethodType.ecocash => 'ECOCASH',
        PaymentMethodType.onemoney => 'ONEMONEY',
        PaymentMethodType.innbucks => 'INNBUCKS',
        PaymentMethodType.cash => 'CASH',
      };

  String get label => switch (this) {
        PaymentMethodType.ecocash => 'EcoCash',
        PaymentMethodType.onemoney => 'OneMoney',
        PaymentMethodType.innbucks => 'InnBucks',
        PaymentMethodType.cash => 'Cash on delivery',
      };

  String get blurb => switch (this) {
        PaymentMethodType.ecocash => 'Approve on your phone',
        PaymentMethodType.onemoney => 'Approve on your phone',
        PaymentMethodType.innbucks => 'Approve in the InnBucks app',
        PaymentMethodType.cash => 'Pay the driver when it arrives',
      };

  /// Whether a phone number is needed and `/payment/initiate` is called.
  bool get requiresOnlinePayment => this != PaymentMethodType.cash;

  /// What the customer must do next, once the prompt has been sent.
  String get waitingInstruction => switch (this) {
        PaymentMethodType.ecocash =>
          'Check your phone for the EcoCash prompt and enter your PIN to '
              'approve. If nothing arrives, dial *151# and choose the pending '
              'approval.',
        PaymentMethodType.onemoney =>
          'Check your phone for the OneMoney prompt and enter your PIN to '
              'approve. If nothing arrives, dial *111# and choose the pending '
              'approval.',
        PaymentMethodType.innbucks =>
          'Open the InnBucks app and approve the payment request, or use the '
              'authorisation code InnBucks sent you.',
        PaymentMethodType.cash => 'Have the cash ready when your driver arrives.',
      };
}

/// Where a payment is in its life.
enum PaymentPhase {
  /// Nothing started.
  idle,

  /// Talking to `/payment/initiate`.
  initiating,

  /// The prompt is on the customer's phone; we are polling for the result.
  awaitingCustomer,

  /// Settled — the money arrived.
  paid,

  /// Terminal failure. [PaymentSession.failureReason] says why in plain words.
  failed,
}

/// Immutable snapshot of the current payment attempt.
@immutable
class PaymentSession {
  const PaymentSession({
    this.phase = PaymentPhase.idle,
    this.paymentId,
    this.orderId,
    this.method,
    this.amount,
    this.rawStatus,
    this.failureReason,
    this.secondsRemaining,
    this.attempt = 0,
  });

  final PaymentPhase phase;
  final String? paymentId;
  final String? orderId;
  final PaymentMethodType? method;

  /// Amount being charged, in the settlement currency.
  final Money? amount;

  /// Backend `PaymentStatus` string, kept for diagnostics — never shown raw.
  final String? rawStatus;

  /// Customer-safe explanation of a failure.
  final String? failureReason;

  /// Countdown shown while waiting, so the wait has a visible end.
  final int? secondsRemaining;

  /// How many times the customer has tried to pay for this order.
  final int attempt;

  bool get isBusy =>
      phase == PaymentPhase.initiating || phase == PaymentPhase.awaitingCustomer;
  bool get isSettled => phase == PaymentPhase.paid;
  bool get canRetry => phase == PaymentPhase.failed;

  PaymentSession copyWith({
    PaymentPhase? phase,
    String? paymentId,
    String? orderId,
    PaymentMethodType? method,
    Money? amount,
    String? rawStatus,
    String? failureReason,
    int? secondsRemaining,
    int? attempt,
    bool clearFailure = false,
  }) =>
      PaymentSession(
        phase: phase ?? this.phase,
        paymentId: paymentId ?? this.paymentId,
        orderId: orderId ?? this.orderId,
        method: method ?? this.method,
        amount: amount ?? this.amount,
        rawStatus: rawStatus ?? this.rawStatus,
        failureReason: clearFailure ? null : (failureReason ?? this.failureReason),
        secondsRemaining: secondsRemaining ?? this.secondsRemaining,
        attempt: attempt ?? this.attempt,
      );
}

/// How long we wait for the customer to approve before calling it expired.
/// Paynow mobile-money prompts do not live much longer than this.
const Duration kPaymentPollInterval = Duration(seconds: 3);
const Duration kPaymentWindow = Duration(minutes: 3);

@Riverpod(keepAlive: true)
class Payment extends _$Payment {
  Timer? _pollTimer;
  DateTime? _deadline;

  @override
  PaymentSession build() {
    ref.onDispose(_stopPolling);
    return const PaymentSession();
  }

  /// Ask the backend to push a payment prompt to the customer's phone.
  ///
  /// Returns true when the prompt was accepted by the provider; the money has
  /// not moved yet at that point — [PaymentPhase.awaitingCustomer] does.
  Future<bool> initiatePayment({
    required String orderId,
    required PaymentMethodType method,
    required String phone,
    String currency = kDefaultCurrency,
    Money? amount,
  }) async {
    if (!method.requiresOnlinePayment) {
      // Cash is settled with the driver; there is nothing to initiate.
      state = PaymentSession(
        phase: PaymentPhase.paid,
        orderId: orderId,
        method: method,
        amount: amount,
        rawStatus: 'CASH_ON_DELIVERY',
      );
      return true;
    }

    _stopPolling();
    state = PaymentSession(
      phase: PaymentPhase.initiating,
      orderId: orderId,
      method: method,
      amount: amount,
      attempt: state.orderId == orderId ? state.attempt + 1 : 1,
    );

    final dio = ref.read(apiClientProvider);
    try {
      final response = await dio.post('/payment/initiate', data: {
        'order_id': orderId,
        'method': method.wireValue,
        'phone': normalisePhone(phone),
        'currency': currency.toUpperCase(),
      });
      _adoptPaymentPayload(
        Map<String, dynamic>.from(response.data as Map),
        method: method,
        orderId: orderId,
      );
      if (state.phase == PaymentPhase.failed) return false;
      _startPolling();
      return true;
    } on DioException catch (e) {
      // A prompt may already be in flight for this order (a retry after a lost
      // response). Adopt it rather than telling the customer it failed.
      if (e.response?.statusCode == 400) {
        final adopted = await _adoptExistingPayment(orderId, method);
        if (adopted) return true;
      }
      state = state.copyWith(
        phase: PaymentPhase.failed,
        failureReason: _readableError(e),
      );
      return false;
    }
  }

  /// Re-attach to a payment that already exists for this order.
  Future<bool> _adoptExistingPayment(
      String orderId, PaymentMethodType method) async {
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get('/payment/order/$orderId');
      _adoptPaymentPayload(
        Map<String, dynamic>.from(response.data as Map),
        method: method,
        orderId: orderId,
      );
      if (state.phase == PaymentPhase.awaitingCustomer) {
        _startPolling();
        return true;
      }
      return state.phase == PaymentPhase.paid;
    } catch (_) {
      return false;
    }
  }

  /// Re-check an order's payment, e.g. when the screen is reopened.
  Future<void> refreshForOrder(String orderId,
      {PaymentMethodType method = PaymentMethodType.ecocash}) async {
    await _adoptExistingPayment(orderId, method);
  }

  void _adoptPaymentPayload(
    Map<String, dynamic> data, {
    required PaymentMethodType method,
    required String orderId,
  }) {
    final status = (data['status'] as String? ?? 'PENDING').toUpperCase();
    final currency = data['currency'] as String? ?? kDefaultCurrency;
    final minor = (data['amount_local_minor'] as num?)?.toInt();
    final amount = minor != null && minor > 0
        ? Money.minorUnits(minor, currency: currency)
        : (data['amount_local'] is num
            ? Money.fromMajor(data['amount_local'] as num, currency: currency)
            : state.amount);

    state = state.copyWith(
      paymentId: data['id'] as String?,
      orderId: orderId,
      method: method,
      amount: amount,
      rawStatus: status,
      phase: _phaseFor(status),
      failureReason: _failureFor(status),
      clearFailure: _phaseFor(status) != PaymentPhase.failed,
    );
  }

  static PaymentPhase _phaseFor(String status) => switch (status) {
        'PAID' => PaymentPhase.paid,
        'PENDING' || 'AWAITING_DELIVERY' => PaymentPhase.awaitingCustomer,
        _ => PaymentPhase.failed,
      };

  static String? _failureFor(String status) => switch (status) {
        'FAILED' => 'Your mobile money provider declined the payment. '
            'Check your balance and try again.',
        'CANCELLED' => 'The payment was cancelled on your phone.',
        'EXPIRED' => 'The payment request expired before it was approved.',
        'REFUNDED' || 'REFUND_PENDING' =>
          'This payment is being refunded, so it cannot be used for this order.',
        _ => null,
      };

  void _startPolling() {
    _stopPolling();
    _deadline = DateTime.now().add(kPaymentWindow);
    state = state.copyWith(secondsRemaining: kPaymentWindow.inSeconds);
    _pollTimer = Timer.periodic(kPaymentPollInterval, (timer) async {
      final paymentId = state.paymentId;
      final deadline = _deadline;
      if (paymentId == null || deadline == null) {
        _stopPolling();
        return;
      }

      final remaining = deadline.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        _stopPolling();
        state = state.copyWith(
          phase: PaymentPhase.failed,
          secondsRemaining: 0,
          failureReason:
              'We did not get a confirmation in time. If you approved the '
              'payment, it may still come through — check your order before '
              'paying again.',
        );
        return;
      }
      state = state.copyWith(secondsRemaining: remaining);

      try {
        final dio = ref.read(apiClientProvider);
        final response = await dio.get('/payment/status/$paymentId');
        final data = Map<String, dynamic>.from(response.data as Map);
        final status = (data['status'] as String? ?? '').toUpperCase();
        if (status.isEmpty) return;
        final phase = _phaseFor(status);
        state = state.copyWith(
          rawStatus: status,
          phase: phase,
          failureReason: _failureFor(status),
          clearFailure: phase != PaymentPhase.failed,
        );
        if (phase != PaymentPhase.awaitingCustomer) _stopPolling();
      } catch (_) {
        // A dropped packet is not a failed payment — keep polling until the
        // window closes.
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Stop waiting without claiming the payment failed (the user backed out).
  void cancelWaiting() {
    _stopPolling();
    state = state.copyWith(
      phase: PaymentPhase.failed,
      failureReason: 'You stopped waiting for the payment. '
          'You can try again, or check your order to see if it went through.',
    );
  }

  /// Clear everything so a new attempt starts clean.
  void reset() {
    _stopPolling();
    _deadline = null;
    state = const PaymentSession();
  }

  /// `07…`, `2637…` and `+2637…` all become `+2637…` (E.164).
  static String normalisePhone(String raw) {
    var digits = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('263')) return '+$digits';
    if (digits.startsWith('0')) return '+263${digits.substring(1)}';
    if (digits.length == 9) return '+263$digits';
    return digits.isEmpty ? '' : '+$digits';
  }

  /// Validate a Zimbabwe mobile number. Returns null when it is fine, or the
  /// message to show under the field.
  static String? validatePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Enter the number your money is on.';
    final e164 = normalisePhone(trimmed);
    if (!RegExp(r'^\+2637[1-8]\d{7}$').hasMatch(e164)) {
      return 'That does not look like a Zimbabwe mobile number '
          '(e.g. 077 123 4567).';
    }
    return null;
  }

  static String _readableError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      final detail = data['detail'] as String;
      if (detail.contains('Payment already exists')) {
        return 'A payment for this order is already in progress. '
            'Check your phone for the prompt.';
      }
      return detail;
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The payment request timed out before it reached your provider. '
            'Nothing was charged — try again.';
      case DioExceptionType.connectionError:
        return 'We could not reach Zvingo. Check your connection and try again.';
      default:
        if (e.response?.statusCode == 503) {
          return 'We cannot confirm today\'s exchange rate, so we will not '
              'charge you at a rate we cannot vouch for. Try again shortly.';
        }
        return 'We could not start the payment. Nothing has been charged.';
    }
  }
}

/// Live exchange rates, used to show what a USD total costs in ZIG or ZAR.
///
/// Hand-written provider: the pinned generator emits a deprecated
/// `AutoDisposeFutureProviderRef` for generated function providers.
final exchangeRatesProvider = FutureProvider<Map<String, double>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final response = await dio.get('/finance/rates');
    final data = Map<String, dynamic>.from(response.data as Map);
    final rates = Map<String, dynamic>.from(data['rates'] as Map? ?? {});
    return {
      for (final entry in rates.entries)
        entry.key.toUpperCase(): (entry.value as num).toDouble(),
    };
  } catch (_) {
    // Settlement in USD always works; the alternatives simply stay hidden.
    return const {'USD': 1.0};
  }
});

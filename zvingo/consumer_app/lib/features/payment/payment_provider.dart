import 'dart:async';
import 'package:consumer_app/core/api_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'payment_provider.g.dart';

enum PaymentMethodType { ecocash, onemoney, innbucks, cash, card }

class PaymentState {
  final String? paymentId;
  final String status; // PENDING, AWAITING_DELIVERY, PAID, FAILED
  final String? error;

  const PaymentState({this.paymentId, this.status = 'idle', this.error});

  PaymentState copyWith({String? paymentId, String? status, String? error}) {
    return PaymentState(
      paymentId: paymentId ?? this.paymentId,
      status: status ?? this.status,
      error: error,
    );
  }
}

@Riverpod(keepAlive: true)
class Payment extends _$Payment {
  Timer? _pollTimer;

  @override
  PaymentState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const PaymentState();
  }

  Future<bool> initiatePayment({
    required String orderId,
    required PaymentMethodType method,
    required String phone,
    String currency = 'USD',
  }) async {
    state = const PaymentState(status: 'initiating');

    try {
      final dio = ref.read(apiClientProvider);
      final methodStr = switch (method) {
        PaymentMethodType.ecocash => 'ECOCASH',
        PaymentMethodType.onemoney => 'ONEMONEY',
        PaymentMethodType.innbucks => 'INNBUCKS',
        PaymentMethodType.cash => 'CASH',
        PaymentMethodType.card => 'CARD',
      };

      final response = await dio.post('/payment/initiate', data: {
        'order_id': orderId,
        'method': methodStr,
        'phone': phone,
        'currency': currency,
      });

      final paymentId = response.data['id'];
      final paymentStatus = response.data['status'];

      state = PaymentState(
        paymentId: paymentId,
        status: paymentStatus ?? 'AWAITING_DELIVERY',
      );

      // Start polling for payment confirmation
      _startPolling(paymentId);
      return true;
    } catch (e) {
      state = PaymentState(status: 'FAILED', error: e.toString());
      return false;
    }
  }

  void _startPolling(String paymentId) {
    _pollTimer?.cancel();
    int attempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts++;
      if (attempts > 40) {
        // 2 minute timeout
        timer.cancel();
        state = state.copyWith(status: 'FAILED', error: 'Payment timed out');
        return;
      }

      try {
        final dio = ref.read(apiClientProvider);
        final response = await dio.get('/payment/status/$paymentId');
        final newStatus = response.data['status'] as String;

        state = state.copyWith(status: newStatus);

        if (newStatus == 'PAID' ||
            newStatus == 'FAILED' ||
            newStatus == 'REFUNDED') {
          timer.cancel();
        }
      } catch (_) {
        // Continue polling on network errors
      }
    });
  }

  void reset() {
    _pollTimer?.cancel();
    state = const PaymentState();
  }
}

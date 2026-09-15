/// Promo-code entry, wired to the real `POST /catalog/promotions/validate`.
///
/// The backend already writes plain-language refusals ("This promo code has
/// expired", "Spend $5.00 more to use this code", "This promo code is not valid
/// for this restaurant"), returned as a 400 `detail`. The app shows that
/// sentence verbatim rather than inventing its own — never a silent no-op, and
/// never a disabled Apply button with no explanation.
library;

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'promo_provider.g.dart';

enum PromoStatus { none, validating, applied, rejected }

@immutable
class PromoState {
  const PromoState({
    this.status = PromoStatus.none,
    this.code,
    this.discount,
    this.freeDelivery = false,
    this.message,
  });

  final PromoStatus status;

  /// The code as typed (upper-cased), kept so it can be re-validated when the
  /// basket changes.
  final String? code;

  /// Discount the server says this code is worth for the current basket.
  final Money? discount;

  /// True when the code waives the delivery fee instead of (or as well as)
  /// discounting the food.
  final bool freeDelivery;

  /// Plain-language outcome — the reason it was refused, or what it saved.
  final String? message;

  bool get isApplied => status == PromoStatus.applied;
  bool get isBusy => status == PromoStatus.validating;
  bool get isRejected => status == PromoStatus.rejected;

  Money discountIn(String currency) =>
      discount ?? Money.zero(currency);
}

@Riverpod(keepAlive: true)
class Promo extends _$Promo {
  @override
  PromoState build() => const PromoState();

  /// Validate [rawCode] against the current basket.
  ///
  /// Returns true when the code applied. The discount is a *preview*: the
  /// server recomputes and redeems it at checkout, and the checkout response's
  /// `discount_total` is what the customer actually gets.
  Future<bool> apply(String rawCode, {required Money subtotal}) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) {
      state = const PromoState(
        status: PromoStatus.rejected,
        message: 'Enter a promo code first.',
      );
      return false;
    }

    state = PromoState(status: PromoStatus.validating, code: code);

    final cart = ref.read(cartProvider);
    final owner = ref.read(cartOwnerProvider);
    final dio = ref.read(apiClientProvider);

    try {
      final response = await dio.post('/catalog/promotions/validate', data: {
        'code': code,
        'order_subtotal_usd': subtotal.major,
        'items': cart
            .map((i) => {
                  'id': i.itemId,
                  'name': i.name,
                  'price': i.unitPrice.major,
                  'quantity': i.quantity,
                })
            .toList(),
        if (owner.id != null) 'restaurant_id': owner.id,
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final discount = Money.fromMajor(
        (data['discount_usd'] as num?) ?? 0,
        currency: subtotal.currency,
      );
      final freeDelivery = data['free_delivery'] as bool? ?? false;

      if (discount.isZero && !freeDelivery) {
        state = PromoState(
          status: PromoStatus.rejected,
          code: code,
          message: 'That code is valid but saves nothing on this basket.',
        );
        return false;
      }

      state = PromoState(
        status: PromoStatus.applied,
        code: code,
        discount: discount,
        freeDelivery: freeDelivery,
        message: _savingsCopy(discount, freeDelivery),
      );
      return true;
    } on DioException catch (e) {
      state = PromoState(
        status: PromoStatus.rejected,
        code: code,
        message: _refusal(e),
      );
      return false;
    }
  }

  /// Re-check the applied code after the basket changed (a promo with a
  /// minimum can stop qualifying when a line is removed).
  Future<void> revalidate({required Money subtotal}) async {
    final code = state.code;
    if (code == null || !state.isApplied) return;
    await apply(code, subtotal: subtotal);
  }

  void clear() => state = const PromoState();

  static String _savingsCopy(Money discount, bool freeDelivery) {
    if (discount.isPositive && freeDelivery) {
      return 'Applied — ${discount.format()} off and free delivery.';
    }
    if (freeDelivery) return 'Applied — free delivery on this order.';
    return 'Applied — ${discount.format()} off this order.';
  }

  static String _refusal(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Checking that code took too long. Try again.';
      case DioExceptionType.connectionError:
        return 'We could not check that code — you appear to be offline.';
      default:
        if (e.response?.statusCode == 401) {
          return 'Sign in to use a promo code.';
        }
        return 'We could not check that code. Try again in a moment.';
    }
  }
}

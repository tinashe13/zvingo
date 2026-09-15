/// Invariants of the ordering funnel that must never regress.
///
/// These are the two things that would silently cost a customer (or Zvingo)
/// money: the minor-unit conversion at the API boundary, and the checkout
/// breakdown reconciling to the total that gets charged.
library;

import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/checkout/order_quote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('converts a JSON price to exact minor units', () {
      expect(Money.fromMajor(12.5).minor, 1250);
      expect(Money.fromMajor(0.1).minor, 10);
      expect(Money.fromMajor(2.675).minor, 268); // half-up, not binary drift
      expect(Money.fromMajor(0).minor, 0);
    });

    test('adding never drifts the way floats do', () {
      // 0.1 + 0.2 != 0.3 in binary floating point.
      final sum = Money.fromMajor(0.1) + Money.fromMajor(0.2);
      expect(sum.minor, 30);
      expect(sum, Money.fromMajor(0.3));
    });

    test('always renders with a currency symbol', () {
      expect(Money.fromMajor(1234.5).format(), r'US$1,234.50');
      expect(
        Money.minorUnits(1250, currency: 'ZIG').format(),
        'ZiG12.50',
      );
      expect(Money.minorUnits(-250).format(), r'-US$2.50');
    });

    test('basis points are integral', () {
      // 15% of $23.33 is $3.4995 -> $3.50 exactly, once.
      expect(Money.fromMajor(23.33).basisPoints(1500).minor, 350);
    });

    test('tryParse rejects junk instead of treating it as zero', () {
      expect(Money.tryParse('2.50')?.minor, 250);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('-3'), isNull);
    });
  });

  group('CartItem', () {
    CartItem line({
      List<CartOptionChoice> choices = const [],
      String? note,
      int quantity = 1,
    }) =>
        CartItem(
          itemId: 'burger',
          name: 'Burger',
          unitBasePrice: Money.fromMajor(6.99),
          quantity: quantity,
          choices: choices,
          specialInstructions: note,
        );

    test('option deltas are folded into the unit price', () {
      final withCheese = line(choices: [
        CartOptionChoice(
          groupId: 'extras',
          groupLabel: 'Extras',
          id: 'cheese',
          label: 'Cheese',
          priceDelta: Money.fromMajor(1.25),
        ),
      ]);
      expect(withCheese.unitPrice.minor, 824);
      expect((withCheese.copyWith(quantity: 3)).lineTotal.minor, 2472);
    });

    test('different configurations are different lines', () {
      final plain = line();
      final noted = line(note: 'no onion');
      final cheesy = line(choices: [
        CartOptionChoice(
          groupId: 'extras',
          groupLabel: 'Extras',
          id: 'cheese',
          label: 'Cheese',
          priceDelta: Money.fromMajor(1.25),
        ),
      ]);
      expect(plain.lineId, isNot(noted.lineId));
      expect(plain.lineId, isNot(cheesy.lineId));
      expect(plain.lineId, line().lineId);
    });
  });

  group('OrderQuote', () {
    OrderQuote build({
      double subtotal = 23.33,
      FulfilmentMode mode = FulfilmentMode.delivery,
      double? deliveryFee = 2.5,
      double tip = 2,
      double discount = 0,
    }) =>
        OrderQuote.forCart(
          subtotal: Money.fromMajor(subtotal),
          mode: mode,
          restaurantDeliveryFee:
              deliveryFee == null ? null : Money.fromMajor(deliveryFee),
          tip: Money.fromMajor(tip),
          discount: Money.fromMajor(discount),
        );

    test('reconciles to the cent', () {
      final quote = build();
      expect(quote.reconciles, isTrue);
      expect(
        quote.total.minor,
        quote.subtotal.minor +
            quote.deliveryFee.minor +
            quote.serviceFee.minor +
            quote.tax.minor +
            quote.tip.minor -
            quote.discount.minor,
      );
    });

    test('service fee is clamped, in cents', () {
      expect(build(subtotal: 1).serviceFee.minor, kServiceFeeMinCents);
      expect(build(subtotal: 500).serviceFee.minor, kServiceFeeMaxCents);
      expect(build(subtotal: 23.33).serviceFee.minor, 350);
    });

    test('pickup removes the delivery fee entirely', () {
      final quote = build(mode: FulfilmentMode.pickup);
      expect(quote.deliveryFee.isZero, isTrue);
      expect(quote.reconciles, isTrue);
    });

    test('a discount never makes the total negative', () {
      final quote = build(subtotal: 5, tip: 0, discount: 100);
      expect(quote.total.minor, 0);
      expect(quote.reconciles, isTrue);
    });

    test('falls back to the backend block formula when there is no fee set', () {
      // $5 per started 5km block, matching app/finance/fee_calculator.py.
      final fee = OrderQuote.estimatedDeliveryFee(
        restaurantLat: -17.8252,
        restaurantLng: 31.0335,
        dropoffLat: -17.8252,
        dropoffLng: 31.0335,
      );
      expect(fee.minor, kDeliveryBlockPriceCents);

      final quote = build(deliveryFee: null);
      expect(quote.deliveryFee.minor, kDeliveryBlockPriceCents);
      expect(quote.reconciles, isTrue);
    });

    test('a promo-funded free delivery zeroes the fee and still reconciles', () {
      final quote = OrderQuote.forCart(
        subtotal: Money.fromMajor(20),
        mode: FulfilmentMode.delivery,
        restaurantDeliveryFee: Money.fromMajor(2.5),
        freeDeliveryFromPromo: true,
      );
      expect(quote.deliveryFee.isZero, isTrue);
      expect(quote.reconciles, isTrue);
    });
  });
}

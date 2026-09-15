/// Unit tests for the order feature's pure logic: payload parsing, the
/// lifecycle→timeline mapping, and the ETA estimator.
///
/// The ETA is the one piece of this feature that computes rather than renders,
/// and the product rule is "never show a number we cannot stand behind", so it
/// is worth asserting rather than eyeballing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_providers.dart';
import 'package:consumer_app/features/order/order_timeline.dart';

/// A realistic `GET /orders/{id}` body (see `backend/app/order/router.py`).
Map<String, dynamic> orderPayload({
  String state = 'PICKED_UP',
  bool withDriver = true,
}) {
  return <String, dynamic>{
    'id': '6512ab34cd56ef7890123456',
    'state': state,
    'total_amount': 18.5,
    'created_at': '2026-09-15T10:00:00',
    'driver_id': withDriver ? 'driver-1' : null,
    'driver_name': withDriver ? 'Tendai Moyo' : null,
    'driver_lat': withDriver ? -17.8300 : null,
    'driver_lng': withDriver ? 31.0500 : null,
    'merchant_id': 'restaurant-1',
    'consumer_id': 'consumer-1',
    'items': [
      {'name': 'Sadza & beef', 'quantity': 2, 'price': 6.0},
      {'name': 'Coke', 'quantity': 1, 'price': 1.5},
    ],
    'pickup_lat': -17.8250,
    'pickup_lng': 31.0450,
    'delivery_lat': -17.8400,
    'delivery_lng': 31.0600,
  };
}

void main() {
  group('order state normalisation', () {
    test('strips the legacy OrderState. prefix', () {
      expect(normaliseOrderState('OrderState.PICKED_UP'), 'PICKED_UP');
      expect(normaliseOrderState('picked_up'), 'PICKED_UP');
      expect(normaliseOrderState(null), 'CREATED');
    });

    test('CANCELLED is terminal but has no rank', () {
      expect(orderStateRank('CANCELLED'), -1);
      expect(isTerminalOrderState('CANCELLED'), isTrue);
      expect(isTerminalOrderState('DELIVERED'), isTrue);
      expect(isTerminalOrderState('PICKED_UP'), isFalse);
    });
  });

  group('timeline', () {
    test('every non-cancelled backend state maps onto exactly one node', () {
      const backendStates = [
        'CREATED',
        'OFFERED',
        'ACCEPTED',
        'ARRIVED_AT_MERCHANT',
        'READY_FOR_PICKUP',
        'PICKED_UP',
        'ARRIVED_AT_CUSTOMER',
        'DELIVERED',
      ];
      for (final state in backendStates) {
        final rank = orderStateRank(state);
        expect(rank, isNonNegative, reason: '$state has no rank');
        final matches =
            kOrderTimeline.where((step) => step.rank == rank).toList();
        expect(matches, hasLength(1),
            reason: '$state must light exactly one node');
      }
    });

    test('node ranks are contiguous and ordered', () {
      for (var i = 0; i < kOrderTimeline.length; i++) {
        expect(kOrderTimeline[i].rank, i);
      }
    });

    test('headline personalises with the courier once assigned', () {
      expect(orderHeadline('PICKED_UP').detail, contains('Your courier'));
      expect(
        orderHeadline('PICKED_UP', driverFirstName: 'Tendai').detail,
        contains('Tendai'),
      );
    });
  });

  group('TrackedOrder parsing', () {
    test('reads the live order payload', () {
      final order = TrackedOrder.fromJson(orderPayload());
      expect(order.state, 'PICKED_UP');
      expect(order.itemCount, 3);
      expect(order.subtotal, closeTo(13.5, 0.001));
      expect(order.driver?.firstName, 'Tendai');
      expect(order.driverPosition, isNotNull);
      expect(order.pickup, isNotNull);
      expect(order.destination, isNotNull);
      expect(order.shortReference, '#123456');
      expect(order.canCancel, isFalse, reason: 'courier already has the food');
      expect(order.canConfirmDelivery, isTrue);
    });

    test('null island coordinates are dropped rather than mapped', () {
      final payload = orderPayload()
        ..['driver_lat'] = 0.0
        ..['driver_lng'] = 0.0;
      expect(TrackedOrder.fromJson(payload).driverPosition, isNull);
    });

    test('fees are derived from the total when the API omits them', () {
      final order = TrackedOrder.fromJson(orderPayload());
      expect(order.hasFeeBreakdown, isFalse);
      expect(order.derivedFees, closeTo(5.0, 0.001));
    });

    test('an itemised payload is reported as itemised', () {
      final payload = orderPayload()
        ..['delivery_fee'] = 2.0
        ..['service_fee'] = 1.0
        ..['tax_amount'] = 2.0;
      expect(TrackedOrder.fromJson(payload).hasFeeBreakdown, isTrue);
    });

    test('cancellable states match the backend consumer-cancel rule', () {
      for (final state in [
        'CREATED',
        'OFFERED',
        'ACCEPTED',
        'READY_FOR_PICKUP'
      ]) {
        expect(
          TrackedOrder.fromJson(orderPayload(state: state)).canCancel,
          isTrue,
          reason: '$state should be cancellable',
        );
      }
      for (final state in ['PICKED_UP', 'ARRIVED_AT_CUSTOMER', 'DELIVERED']) {
        expect(
          TrackedOrder.fromJson(orderPayload(state: state)).canCancel,
          isFalse,
          reason: '$state must not offer self-service cancel',
        );
      }
    });

    test('map-style access keeps pre-migration screens working', () {
      final order = TrackedOrder.fromJson(orderPayload());
      expect(order['id'], order.id);
      expect(order['state'], 'PICKED_UP');
      expect(order['restaurant_name'], isNull);
    });
  });

  group('OrderEtaEstimator', () {
    test('a finished order has no ETA', () {
      final estimator = OrderEtaEstimator();
      final order = TrackedOrder.fromJson(orderPayload(state: 'DELIVERED'));
      expect(estimator.estimate(order).confidence, EtaConfidence.finished);
    });

    test('a live courier position gives a precise minute count', () {
      final estimator = OrderEtaEstimator();
      final order = TrackedOrder.fromJson(orderPayload());
      final eta =
          estimator.estimate(order, driverPosition: order.driverPosition);
      expect(eta.confidence, EtaConfidence.precise);
      expect(eta.minutes, isNotNull);
      expect(eta.minutes, greaterThan(0));
      expect(eta.label, isNot(contains('–')));
    });

    test('no courier position yet gives an honest range, not a number', () {
      final estimator = OrderEtaEstimator();
      final order = TrackedOrder.fromJson(
        orderPayload(state: 'ACCEPTED', withDriver: false),
      );
      final eta = estimator.estimate(order);
      expect(eta.confidence, EtaConfidence.estimated);
      expect(eta.low, lessThan(eta.high!));
      expect(eta.label, contains('–'));
    });

    test('no coordinates at all says "Updating…" rather than guessing', () {
      final estimator = OrderEtaEstimator();
      final payload = orderPayload(state: 'CREATED', withDriver: false)
        ..['pickup_lat'] = null
        ..['pickup_lng'] = null
        ..['delivery_lat'] = null
        ..['delivery_lng'] = null;
      final eta = estimator.estimate(TrackedOrder.fromJson(payload));
      expect(eta.confidence, EtaConfidence.unknown);
      expect(eta.label, 'Updating…');
    });

    test('a server-supplied ETA wins over the client estimate', () {
      final estimator = OrderEtaEstimator();
      final payload = orderPayload()..['eta_minutes'] = 7;
      final eta = estimator.estimate(TrackedOrder.fromJson(payload));
      expect(eta.confidence, EtaConfidence.precise);
      expect(eta.minutes, 7);
    });

    test('small changes are smoothed, they never jitter minute to minute', () {
      final estimator = OrderEtaEstimator();
      final order = TrackedOrder.fromJson(orderPayload());
      final destination = order.destination!;

      // First fix anchors the estimate.
      final first =
          estimator.estimate(order, driverPosition: order.driverPosition);
      // Next fix is right on the doorstep: the drop is clamped, not instant.
      final second = estimator.estimate(order, driverPosition: destination);
      expect(second.minutes, greaterThanOrEqualTo(first.minutes! - 3));
      expect(second.minutes, lessThanOrEqualTo(first.minutes!));

      // It does converge, though — repeated fixes walk it down.
      var latest = second;
      for (var i = 0; i < 10; i++) {
        latest = estimator.estimate(order, driverPosition: destination);
      }
      expect(latest.minutes, lessThanOrEqualTo(3));
    });

    test('reset drops the smoothing history', () {
      final estimator = OrderEtaEstimator();
      final order = TrackedOrder.fromJson(orderPayload());
      estimator.estimate(order, driverPosition: order.destination);
      estimator.reset();
      final far = estimator.estimate(
        order,
        driverPosition: const LatLng(-17.9500, 31.2000),
      );
      expect(far.minutes, greaterThan(5));
    });
  });

  group('error copy', () {
    test('falls back to plain language for an unknown error', () {
      expect(
        orderErrorMessage(Exception('boom'), fallback: 'Please try again.'),
        'Please try again.',
      );
    });
  });
}

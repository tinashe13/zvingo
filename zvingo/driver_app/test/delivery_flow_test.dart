import 'package:driver_app/models/delivery_state.dart';
import 'package:driver_app/models/order_offer.dart';
import 'package:driver_app/providers/delivery_provider.dart';
import 'package:driver_app/services/location_service.dart';
import 'package:driver_app/services/pub_sub_service.dart';
import 'package:driver_app/widgets/connection_status_banner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the delivery loop — the path that earns everyone money.
///
/// These are deliberately free of Hive, the network and the widget tree, so
/// they run anywhere and fail for exactly one reason. They also act as the
/// compile check for `lib/services`, `lib/models` and
/// `lib/providers/delivery_provider.dart`, which nothing else in `test/`
/// imports.
void main() {
  group('offer expiry', () {
    test('a fresh offer is live and reports its full window', () {
      final offer = _offer(timeoutSeconds: 45);
      expect(offer.isExpired, isFalse);
      expect(offer.remainingSeconds, closeTo(45, 1));
    });

    test('an offer past its window is expired and reports zero', () {
      final offer = _offer(
        timeoutSeconds: 45,
        receivedAt:
            DateTime.now().millisecondsSinceEpoch - const Duration(seconds: 60).inMilliseconds,
      );
      expect(offer.isExpired, isTrue);
      // Never negative: the countdown bar divides by this.
      expect(offer.remainingSeconds, 0);
    });

    test('remaining seconds never exceed the window', () {
      final offer = _offer(
        timeoutSeconds: 45,
        receivedAt: DateTime.now().millisecondsSinceEpoch + 10000,
      );
      expect(offer.remainingSeconds, lessThanOrEqualTo(45));
    });
  });

  group('payout and cash', () {
    test('payout is the driver share of the fee plus the whole tip', () {
      final offer = _offer(deliveryFeeCents: 400, tipCents: 150);
      // 0.85 * 400 = 340, + 150 tip.
      expect(offer.payoutCents(), 490);
    });

    test('a cash order tells the driver exactly what to collect', () {
      final offer = _offer(
        paymentMethod: PaymentMethod.cash,
        totalCents: 1275,
      );
      expect(offer.cashToCollectCents, 1275);
    });

    test('a prepaid order asks the driver to collect nothing', () {
      final offer = _offer(
        paymentMethod: PaymentMethod.ecocash,
        totalCents: 1275,
      );
      expect(offer.cashToCollectCents, 0);
    });
  });

  group('resuming a delivery from /dispatch/state', () {
    test('GeoJSON coordinates are read as [lng, lat], not [lat, lng]', () {
      final restored = OrderOffer.fromDispatchState({
        'order_id': 'abc123def456',
        'short_id': 'ZVDEF456',
        'state': 'PICKED_UP',
        'pickup': {
          'type': 'Point',
          'coordinates': [31.0492, -17.8216],
        },
        'dropoff': {
          'type': 'Point',
          'coordinates': [31.0530, -17.8248],
        },
      });

      expect(restored, isNotNull);
      // Harare is at roughly -17.8 lat, 31.0 lng. Swapping these would send a
      // driver to a point off the coast of Somalia.
      expect(restored!.pickupLat, closeTo(-17.8216, 0.0001));
      expect(restored.pickupLng, closeTo(31.0492, 0.0001));
      expect(restored.hasPickupCoords, isTrue);
      expect(restored.hasDeliveryCoords, isTrue);
    });

    test('an order with no id cannot be restored', () {
      expect(OrderOffer.fromDispatchState(const {'state': 'ACCEPTED'}), isNull);
    });

    test('a missing dropoff leaves the coordinates unusable, not zeroed-valid',
        () {
      final restored = OrderOffer.fromDispatchState({
        'order_id': 'abc123def456',
        'pickup': {
          'type': 'Point',
          'coordinates': [31.0492, -17.8216],
        },
      });
      expect(restored!.hasDeliveryCoords, isFalse);
    });

    test('a short id is derived when the server does not send one', () {
      final restored = OrderOffer.fromDispatchState({
        'order_id': '65f1a2b3c4d5e6f7a8b9c0d1',
      });
      expect(restored!.shortId, 'ZVB9C0D1');
    });
  });

  group('delivery state machine', () {
    test('a pending offer is not an active delivery', () {
      expect(DeliveryState.offered.isActive, isFalse);
      expect(DeliveryState.completed.isActive, isFalse);
      expect(DeliveryState.enRoutePickup.isActive, isTrue);
    });

    test('PICKED_UP is reported at the pickup step, not one step later', () {
      // Regression: this used to be reported from enRouteDelivery, so a driver
      // who collected an order and closed the app was still recorded as
      // standing empty-handed at the restaurant.
      expect(DeliveryState.pickedUp.backendState, 'PICKED_UP');
      expect(DeliveryState.enRouteDelivery.backendState, isNull);
    });

    test('accepted steps report nothing — the server already set ACCEPTED', () {
      expect(DeliveryState.accepted.backendState, isNull);
      expect(DeliveryState.enRoutePickup.backendState, isNull);
    });

    test('collection is the point of no return', () {
      expect(DeliveryState.arrivedPickup.hasCollectedOrder, isFalse);
      expect(DeliveryState.pickedUp.hasCollectedOrder, isTrue);
      expect(DeliveryState.enRouteDelivery.hasCollectedOrder, isTrue);
    });

    test('backend states map onto the right step', () {
      expect(
        DeliveryState.fromBackendState('ARRIVED_AT_MERCHANT'),
        DeliveryState.arrivedPickup,
      );
      expect(
        DeliveryState.fromBackendState('READY_FOR_PICKUP'),
        DeliveryState.arrivedPickup,
      );
      expect(
        DeliveryState.fromBackendState('PICKED_UP'),
        DeliveryState.enRouteDelivery,
      );
      expect(
        DeliveryState.fromBackendState('CANCELLED'),
        DeliveryState.completed,
      );
      expect(DeliveryState.fromBackendState(null), DeliveryState.completed);
    });

    test('every step answers "where am I going"', () {
      for (final state in DeliveryState.values) {
        expect(state.destinationHeadline, isNotEmpty);
      }
    });

    test('terminal states have no way out', () {
      expect(DeliveryState.completed.validTransitions, isEmpty);
      expect(DeliveryState.completed.isTerminal, isTrue);
    });
  });

  group('DeliveryFlowState', () {
    test('an offer on screen does not block going offline', () {
      final state = DeliveryFlowState(
        deliveryState: DeliveryState.offered,
        currentOffer: _offer(),
      );
      expect(state.hasActiveDelivery, isFalse);
      expect(state.hasPendingOffer, isTrue);
    });

    test('an expired offer is no longer a pending offer', () {
      final state = DeliveryFlowState(
        deliveryState: DeliveryState.offered,
        currentOffer: _offer(),
        offerExpired: true,
      );
      expect(state.hasPendingOffer, isFalse);
    });

    test('an active step without an order id is not an active delivery', () {
      // Guards against a half-restored state latching the driver into a
      // delivery that does not exist.
      const state = DeliveryFlowState(deliveryState: DeliveryState.pickedUp);
      expect(state.hasActiveDelivery, isFalse);
      expect(state.activeJob, isNull);
    });

    test('the accepted offer survives as the active job', () {
      // Regression: acceptance used to clear the offer, which wiped the only
      // coordinates the navigation screens had.
      final offer = _offer();
      final state = DeliveryFlowState(
        deliveryState: DeliveryState.enRoutePickup,
        currentOffer: offer,
        activeOrderId: offer.orderId,
      );
      expect(state.hasActiveDelivery, isTrue);
      expect(state.activeJob?.pickupLat, offer.pickupLat);
    });

    test('errors and notices are one-shot and never carried forward', () {
      const state = DeliveryFlowState(error: 'boom');
      expect(state.copyWith(isLoading: true).error, isNull);
    });

    test('the connection message can be cleared, not just replaced', () {
      const state = DeliveryFlowState(connectionMessage: 'no signal');
      expect(
        state.copyWith(
          connectionStatus: ConnectionStatus.connected,
          clearConnectionMessage: true,
        ).connectionMessage,
        isNull,
      );
    });
  });

  group('PubSubService', () {
    test('starts offline and reports it synchronously and on the stream', () {
      final service = PubSubService();
      addTearDown(service.dispose);

      expect(service.status, ConnectionStatus.offline);
      expect(service.isConnected, isFalse);
      expect(service.statusStream, emits(ConnectionStatus.offline));
    });

    test('an empty driver id fails loudly instead of retrying forever', () {
      final service = PubSubService();
      addTearDown(service.dispose);

      service.connect('');
      expect(service.status, ConnectionStatus.failed);
      expect(service.statusMessage, isNotNull);
      expect(service.isActive, isFalse);
    });

    test('wire error codes map to the cases the UI handles', () {
      expect(
        PubSubErrorCode.fromWire('offer_unavailable'),
        PubSubErrorCode.offerUnavailable,
      );
      expect(
        PubSubErrorCode.fromWire('delivery_action_rejected'),
        PubSubErrorCode.deliveryActionRejected,
      );
      expect(PubSubErrorCode.fromWire('something_new'), PubSubErrorCode.unknown);
      expect(PubSubErrorCode.fromWire(null), PubSubErrorCode.unknown);
    });
  });

  group('LocationStartResult', () {
    test('success carries whether tracking is foreground-only', () {
      const result = LocationStartResult.success(foregroundOnly: true);
      expect(result.started, isTrue);
      expect(result.failure, isNull);
      expect(result.foregroundOnly, isTrue);
    });

    test('a failure names which of the four problems it is', () {
      const result =
          LocationStartResult.failed(LocationStartFailure.deniedForever);
      expect(result.started, isFalse);
      expect(result.failure, LocationStartFailure.deniedForever);
    });
  });
}

OrderOffer _offer({
  int timeoutSeconds = 45,
  int? receivedAt,
  int deliveryFeeCents = 350,
  int tipCents = 0,
  int totalCents = 0,
  PaymentMethod paymentMethod = PaymentMethod.ecocash,
}) {
  return OrderOffer(
    orderId: 'order-1',
    shortId: 'ZVTEST1',
    merchantName: 'Chicken Inn Samora',
    merchantAddress: '2 Samora Machel Ave, Harare',
    pickupLat: -17.8216,
    pickupLng: 31.0492,
    customerName: 'Tinashe M.',
    customerAddress: '14 Selous Ave, Harare',
    deliveryLat: -17.8248,
    deliveryLng: 31.0530,
    deliveryFeeCents: deliveryFeeCents,
    tipCents: tipCents,
    totalCents: totalCents,
    paymentMethod: paymentMethod,
    timeoutSeconds: timeoutSeconds,
    receivedAt: receivedAt,
  );
}

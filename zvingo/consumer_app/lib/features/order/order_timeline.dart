/// Customer-facing presentation of the order lifecycle: the status headline,
/// the six-node timeline, and the ETA estimator.
///
/// ## Why six nodes and not nine
///
/// The backend has nine states (`backend/app/order/state_machine.py`) but a
/// customer cannot tell `ARRIVED_AT_MERCHANT` from `READY_FOR_PICKUP` — both
/// mean "the kitchen stage" — and `CREATED`/`OFFERED` are both "we have your
/// order". Showing a step the backend cannot actually distinguish would be a
/// timeline that lies. Each node below maps onto exactly one rank from
/// [kOrderStateRank], so a node lights up only when the backend really says so.
///
/// ## Why the ETA is computed on the client
///
/// The backend does not publish an ETA today (see the C3 report's backend-gap
/// list). Rather than print a confident number the server never promised, the
/// estimator degrades in three steps:
///
/// 1. courier position known → a single smoothed minute count;
/// 2. only the restaurant→destination leg known → an honest **range**;
/// 3. nothing known → "Updating…", never a fabricated number.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/order/order_models.dart';

/// One node of the tracking timeline.
class OrderTimelineStep {
  const OrderTimelineStep({
    required this.rank,
    required this.title,
    required this.icon,
    required this.pendingCopy,
    required this.activeCopy,
    required this.doneCopy,
  });

  /// The [kOrderStateRank] value at which this node becomes the current one.
  final int rank;
  final String title;
  final IconData icon;

  /// Copy shown before the order reaches this node.
  final String pendingCopy;

  /// Copy shown while this node is the current one.
  final String activeCopy;

  /// Copy shown once the order has moved past this node.
  final String doneCopy;
}

/// The six nodes, in order. Ranks line up 1:1 with [kOrderStateRank].
const List<OrderTimelineStep> kOrderTimeline = <OrderTimelineStep>[
  OrderTimelineStep(
    rank: 0,
    title: 'Order placed',
    icon: Icons.receipt_long_rounded,
    pendingCopy: 'Sending your order to the restaurant',
    activeCopy: 'We have your order and are finding a courier',
    doneCopy: 'Your order reached the restaurant',
  ),
  OrderTimelineStep(
    rank: 1,
    title: 'Restaurant confirmed',
    icon: Icons.verified_rounded,
    pendingCopy: 'Waiting for the restaurant to accept',
    activeCopy: 'The restaurant accepted your order',
    doneCopy: 'Accepted by the restaurant',
  ),
  OrderTimelineStep(
    rank: 2,
    title: 'Preparing your food',
    icon: Icons.restaurant_rounded,
    pendingCopy: 'The kitchen starts once the order is accepted',
    activeCopy: 'Your food is being cooked and packed',
    doneCopy: 'Cooked, packed and handed over',
  ),
  OrderTimelineStep(
    rank: 3,
    title: 'Picked up',
    icon: Icons.delivery_dining_rounded,
    pendingCopy: 'Your courier collects the order at the restaurant',
    activeCopy: 'Your courier has your order and is on the way',
    doneCopy: 'Collected from the restaurant',
  ),
  OrderTimelineStep(
    rank: 4,
    title: 'Almost there',
    icon: Icons.location_on_rounded,
    pendingCopy: 'We will tell you the moment your courier arrives',
    activeCopy: 'Your courier has arrived — meet them outside',
    doneCopy: 'Your courier reached you',
  ),
  OrderTimelineStep(
    rank: 5,
    title: 'Delivered',
    icon: Icons.check_circle_rounded,
    pendingCopy: 'Enjoy it when it lands',
    activeCopy: 'Delivered — enjoy your meal',
    doneCopy: 'Delivered — enjoy your meal',
  ),
];

/// The one-second-glance headline for an order state.
class OrderHeadline {
  const OrderHeadline({
    required this.title,
    required this.detail,
    required this.icon,
    required this.tone,
  });

  /// Big, short, the largest thing on the screen.
  final String title;

  /// One supporting sentence.
  final String detail;
  final IconData icon;
  final ZvTone tone;

  Color get color => tone.foreground;
  Color get surface => tone.surface;
}

/// Headline copy for [state]. [driverFirstName] personalises it once a courier
/// is assigned.
OrderHeadline orderHeadline(String state, {String? driverFirstName}) {
  final courier = (driverFirstName == null || driverFirstName.isEmpty)
      ? 'Your courier'
      : driverFirstName;
  switch (state) {
    case 'CREATED':
      return const OrderHeadline(
        title: 'Order placed',
        detail: 'The restaurant is about to confirm your order.',
        icon: Icons.receipt_long_rounded,
        tone: ZvTone.warning,
      );
    case 'OFFERED':
      return const OrderHeadline(
        title: 'Finding a courier',
        detail: 'We are matching your order with a courier nearby.',
        icon: Icons.person_search_rounded,
        tone: ZvTone.warning,
      );
    case 'ACCEPTED':
      return const OrderHeadline(
        title: 'Being prepared',
        detail: 'The restaurant accepted your order and started cooking.',
        icon: Icons.restaurant_rounded,
        tone: ZvTone.info,
      );
    case 'ARRIVED_AT_MERCHANT':
      return OrderHeadline(
        title: 'Being prepared',
        detail: '$courier is waiting at the restaurant for your order.',
        icon: Icons.storefront_rounded,
        tone: ZvTone.info,
      );
    case 'READY_FOR_PICKUP':
      return const OrderHeadline(
        title: 'Ready for pickup',
        detail: 'Your food is packed and waiting for the courier.',
        icon: Icons.shopping_bag_rounded,
        tone: ZvTone.info,
      );
    case 'PICKED_UP':
      return OrderHeadline(
        title: 'On the way',
        detail: '$courier has your order and is heading to you.',
        icon: Icons.delivery_dining_rounded,
        tone: ZvTone.info,
      );
    case 'ARRIVED_AT_CUSTOMER':
      return OrderHeadline(
        title: 'Arriving now',
        detail: '$courier is outside — head down to meet them.',
        icon: Icons.location_on_rounded,
        tone: ZvTone.success,
      );
    case 'DELIVERED':
      return const OrderHeadline(
        title: 'Delivered',
        detail: 'Enjoy your meal. Thanks for ordering with Zvingo.',
        icon: Icons.check_circle_rounded,
        tone: ZvTone.success,
      );
    case 'CANCELLED':
      return const OrderHeadline(
        title: 'Cancelled',
        detail: 'This order was cancelled and will not be delivered.',
        icon: Icons.cancel_rounded,
        tone: ZvTone.error,
      );
    default:
      return const OrderHeadline(
        title: 'Order in progress',
        detail: 'We are keeping an eye on your order.',
        icon: Icons.schedule_rounded,
        tone: ZvTone.neutral,
      );
  }
}

/// How confident the ETA is.
enum EtaConfidence {
  /// A single minute count derived from the courier's live position.
  precise,

  /// A range derived from the restaurant→destination leg and the order state.
  estimated,

  /// Not enough information. The UI must say "Updating…", not guess.
  unknown,

  /// The order is finished — there is nothing to arrive.
  finished,
}

/// The ETA the tracking screen renders.
@immutable
class OrderEta {
  const OrderEta._(this.confidence)
      : minutes = null,
        low = null,
        high = null;

  const OrderEta.precise(int this.minutes)
      : confidence = EtaConfidence.precise,
        low = null,
        high = null;

  const OrderEta.estimated(int this.low, int this.high)
      : confidence = EtaConfidence.estimated,
        minutes = null;

  static const OrderEta unknown = OrderEta._(EtaConfidence.unknown);
  static const OrderEta finished = OrderEta._(EtaConfidence.finished);

  final EtaConfidence confidence;

  /// Set only when [confidence] is [EtaConfidence.precise].
  final int? minutes;

  /// Set only when [confidence] is [EtaConfidence.estimated].
  final int? low;
  final int? high;

  /// Plain-text rendering, used for the shell banner and accessibility.
  String get label {
    switch (confidence) {
      case EtaConfidence.precise:
        final m = minutes ?? 0;
        return m <= 1 ? 'Any minute now' : '$m min';
      case EtaConfidence.estimated:
        return '$low–$high min';
      case EtaConfidence.unknown:
        return 'Updating…';
      case EtaConfidence.finished:
        return '';
    }
  }

  /// One-line explanation of how firm the number is (§ honesty).
  String get qualifier {
    switch (confidence) {
      case EtaConfidence.precise:
        return 'Live estimate from your courier';
      case EtaConfidence.estimated:
        return 'Typical time for this trip';
      case EtaConfidence.unknown:
        return 'We will show a time as soon as we can';
      case EtaConfidence.finished:
        return '';
    }
  }

  bool get hasValue => confidence != EtaConfidence.finished;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderEta &&
          other.confidence == confidence &&
          other.minutes == minutes &&
          other.low == low &&
          other.high == high;

  @override
  int get hashCode => Object.hash(confidence, minutes, low, high);
}

/// Client-side ETA estimator with smoothing.
///
/// A raw distance/speed estimate jitters every time a GPS fix lands. The
/// smoother lets the displayed value move at most
/// [_maxDriftPerUpdateMinutes] per update towards the raw estimate, so it
/// walks down rather than flickering — except when the raw estimate moves by
/// more than [_jumpThresholdMinutes], which means something real happened
/// (a reroute, a long stop) and hiding it would be the dishonest choice.
class OrderEtaEstimator {
  /// Average effective urban speed, including stops and traffic.
  static const double _averageSpeedKmh = 22;

  /// Straight-line distance under-reads road distance.
  static const double _detourFactor = 1.35;

  /// Parking, finding the door, handover.
  static const int _handoverMinutes = 2;

  static const int _maxDriftPerUpdateMinutes = 3;
  static const int _jumpThresholdMinutes = 10;

  /// Remaining kitchen time per rank, as a low/high window in minutes.
  static const Map<int, (int, int)> _prepWindow = <int, (int, int)>{
    0: (12, 22),
    1: (10, 18),
    2: (4, 10),
  };

  static const Distance _distance = Distance();

  double? _smoothed;

  /// Drops the smoothing history — call when the tracked order changes.
  void reset() => _smoothed = null;

  /// Travel time in minutes between two points at [_averageSpeedKmh].
  static double _travelMinutes(LatLng from, LatLng to) {
    final km = _distance.as(LengthUnit.Kilometer, from, to) * _detourFactor;
    return (km / _averageSpeedKmh) * 60;
  }

  /// Produces the ETA for [order], given the freshest courier position.
  OrderEta estimate(TrackedOrder order, {LatLng? driverPosition}) {
    if (order.isTerminal) {
      reset();
      return OrderEta.finished;
    }

    // A server-supplied ETA always wins — it knows about traffic and kitchen
    // load, and we would rather show the platform's own promise.
    final server = order.serverEtaMinutes;
    if (server != null && server >= 0) {
      return OrderEta.precise(_smooth(server.toDouble()));
    }

    final rank = orderStateRank(order.state);
    final destination = order.destination;
    final courier = driverPosition ?? order.driverPosition;

    // Stage 1 — the courier is carrying the food and we know where they are.
    if (rank >= 3 && courier != null && destination != null) {
      final raw = _travelMinutes(courier, destination) + _handoverMinutes;
      return OrderEta.precise(_smooth(raw));
    }

    // The courier is at/near the restaurant: remaining prep + the whole leg.
    final pickup = order.pickup;
    if (destination != null && (pickup != null || courier != null)) {
      final origin = pickup ?? courier!;
      final leg = _travelMinutes(origin, destination) + _handoverMinutes;
      final window = _prepWindow[rank] ?? const (0, 4);
      final low = (leg + window.$1).round();
      final high = (leg + window.$2).round();
      if (rank >= 3) {
        // Carrying the food but no live fix yet — the midpoint is the best we
        // can honestly say, and it is still a range.
        return OrderEta.estimated(low.clamp(1, 240), high.clamp(2, 240));
      }
      return OrderEta.estimated(low.clamp(5, 240), high.clamp(6, 240));
    }

    // Stage 3 — we genuinely do not know. Say so.
    return OrderEta.unknown;
  }

  int _smooth(double raw) {
    final target = raw < 1 ? 1.0 : raw;
    final previous = _smoothed;
    if (previous == null) {
      _smoothed = target;
      return target.round();
    }
    final delta = target - previous;
    if (delta.abs() > _jumpThresholdMinutes) {
      _smoothed = target;
    } else {
      _smoothed = previous +
          delta.clamp(
            -_maxDriftPerUpdateMinutes.toDouble(),
            _maxDriftPerUpdateMinutes.toDouble(),
          );
    }
    return _smoothed!.round().clamp(1, 240);
  }
}

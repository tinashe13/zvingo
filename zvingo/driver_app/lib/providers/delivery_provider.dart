import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api_client.dart';
import '../models/delivery_state.dart';
import '../models/order_offer.dart';
import '../services/location_service.dart';
import '../services/pub_sub_service.dart';
import '../widgets/connection_status_banner.dart';

/// Why the driver cannot be located, in a form the UI can act on.
typedef LocationIssue = LocationStartFailure;

/// Everything the delivery flow needs to render, in one immutable value.
@immutable
class DeliveryFlowState {
  /// Which step of the delivery the driver is on.
  final DeliveryState deliveryState;

  /// The offer on screen, or — once accepted — the job being carried.
  ///
  /// It is deliberately **not** cleared on acceptance. Every downstream screen
  /// navigates using the coordinates that live here; wiping it on accept is
  /// what used to send drivers to a hardcoded point in central Harare.
  final OrderOffer? currentOffer;

  final String? activeOrderId;
  final String? activeOrderShortId;

  /// An accept / decline / complete request is in flight.
  final bool isLoading;

  /// Something went wrong and the driver needs to know. Plain language only —
  /// never an HTTP status or an exception.
  final String? error;

  /// Something happened that is not the driver's fault and is not an error,
  /// e.g. another driver took the order first.
  final String? notice;

  /// Driver take-home for the active job, in cents.
  final int? earningsCents;

  /// True once the shift is running: socket up, dash session open, GPS
  /// streaming.
  final bool isOnline;

  /// A go-online / go-offline request is in flight.
  final bool isSwitchingShift;

  /// The offer on screen has run out of time. Kept visible for a beat rather
  /// than vanishing, so the driver understands why the card stopped working.
  final bool offerExpired;

  /// Realtime link state, mirrored from [PubSubService].
  final ConnectionStatus connectionStatus;

  /// Plain-language detail for [connectionStatus], when there is any.
  final String? connectionMessage;

  /// Set when location could not be started; drives the explanation shown on
  /// the home screen.
  final LocationIssue? locationIssue;

  /// True when the OS granted only "while using the app", so tracking dies
  /// when the phone is pocketed.
  final bool locationForegroundOnly;

  const DeliveryFlowState({
    this.deliveryState = DeliveryState.completed,
    this.currentOffer,
    this.activeOrderId,
    this.activeOrderShortId,
    this.isLoading = false,
    this.error,
    this.notice,
    this.earningsCents,
    this.isOnline = false,
    this.isSwitchingShift = false,
    this.offerExpired = false,
    this.connectionStatus = ConnectionStatus.offline,
    this.connectionMessage,
    this.locationIssue,
    this.locationForegroundOnly = false,
  });

  /// True while the driver is actually carrying a job.
  ///
  /// A pending offer does not count: a card on screen is not a commitment, so
  /// it must not block going offline. Requiring an order id as well means a
  /// half-restored state can never latch the driver into a delivery that does
  /// not exist.
  bool get hasActiveDelivery =>
      deliveryState.isActive && activeOrderId != null;

  /// True when there is a live, still-valid offer to decide on.
  bool get hasPendingOffer =>
      deliveryState == DeliveryState.offered &&
      currentOffer != null &&
      !offerExpired;

  /// The order the driver has committed to, or null.
  OrderOffer? get activeJob => hasActiveDelivery ? currentOffer : null;

  DeliveryFlowState copyWith({
    DeliveryState? deliveryState,
    OrderOffer? currentOffer,
    bool clearOffer = false,
    String? activeOrderId,
    bool clearActiveOrder = false,
    String? activeOrderShortId,
    bool? isLoading,
    String? error,
    String? notice,
    int? earningsCents,
    bool? isOnline,
    bool? isSwitchingShift,
    bool? offerExpired,
    ConnectionStatus? connectionStatus,
    String? connectionMessage,
    bool clearConnectionMessage = false,
    LocationIssue? locationIssue,
    bool clearLocationIssue = false,
    bool? locationForegroundOnly,
  }) {
    return DeliveryFlowState(
      deliveryState: deliveryState ?? this.deliveryState,
      currentOffer: clearOffer ? null : (currentOffer ?? this.currentOffer),
      activeOrderId:
          clearActiveOrder ? null : (activeOrderId ?? this.activeOrderId),
      activeOrderShortId: clearActiveOrder
          ? null
          : (activeOrderShortId ?? this.activeOrderShortId),
      isLoading: isLoading ?? this.isLoading,
      // `error` and `notice` are one-shot: they are passed explicitly or
      // cleared, never carried forward, so a stale message cannot reappear on
      // an unrelated rebuild.
      error: error,
      notice: notice,
      earningsCents: earningsCents ?? this.earningsCents,
      isOnline: isOnline ?? this.isOnline,
      isSwitchingShift: isSwitchingShift ?? this.isSwitchingShift,
      offerExpired: offerExpired ?? this.offerExpired,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      connectionMessage: clearConnectionMessage
          ? null
          : (connectionMessage ?? this.connectionMessage),
      locationIssue:
          clearLocationIssue ? null : (locationIssue ?? this.locationIssue),
      locationForegroundOnly:
          locationForegroundOnly ?? this.locationForegroundOnly,
    );
  }
}

/// Owns the offer → accept → pickup → deliver loop.
///
/// Two rules shape everything here:
///
/// 1. **Money-moving actions go over REST, not the socket.** Accept, complete
///    and each state transition need a synchronous answer — a 409 means
///    another driver won the race and the app has to say so *now*. The
///    WebSocket stays the push channel (offers, order updates, refusals) and a
///    best-effort fallback when REST cannot get through.
/// 2. **Local state never runs ahead of the server on anything irreversible.**
///    Completing a delivery clears the job only after the backend has accepted
///    it. The old code cleared first and logged the failure, which meant a
///    driver whose completion failed lost the job from their screen and was
///    never paid for it.
class DeliveryNotifier extends StateNotifier<DeliveryFlowState> {
  final ApiClient _apiClient;

  final PubSubService _pubSub = PubSubService();
  LocationService? _locationService;
  StreamSubscription<ConnectionStatus>? _statusSub;

  Timer? _offerTicker;
  String? _driverId;

  DeliveryNotifier(this._apiClient) : super(const DeliveryFlowState()) {
    _pubSub.onOffer = receiveOffer;
    _pubSub.onOrderUpdate = _onOrderUpdate;
    _pubSub.onError = _onPubSubError;
    _statusSub = _pubSub.statusStream.listen((status) {
      if (!mounted) return;
      final message = _pubSub.statusMessage;
      state = state.copyWith(
        connectionStatus: status,
        connectionMessage: message,
        clearConnectionMessage: message == null,
        // The listener must not resurrect a one-shot error/notice that the UI
        // has already shown, so re-state them as they are.
        error: state.error,
        notice: state.notice,
      );
    });
  }

  // ── Shift ──────────────────────────────────────────────────────────────

  /// Go on shift: open the socket, register the dash session, start tracking.
  ///
  /// The socket is opened **first** so the Redis subscription exists before the
  /// driver becomes dispatchable. The backend also caches an offer published in
  /// that window and flushes it on connect, but closing the gap is cheaper than
  /// relying on the safety net.
  Future<void> goOnline(String userId) async {
    if (userId.isEmpty) {
      state = state.copyWith(
        error: "We couldn't identify your account. Sign out and back in.",
      );
      return;
    }
    _driverId = userId;
    state = state.copyWith(isSwitchingShift: true, error: null, notice: null);

    _pubSub.connect(userId);

    // Register the dash session so dispatch can see this driver. A position is
    // nice to have here; failing to get one must not stop the shift, because
    // the location stream below will supply one shortly.
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
      } catch (e) {
        debugPrint('DeliveryNotifier: no fix for dash session: $e');
      }
      await _apiClient.updateDashSession(
        active: true,
        lat: position?.latitude,
        lng: position?.longitude,
        radius: 10,
      );
    } catch (e) {
      debugPrint('DeliveryNotifier: dash session failed: $e');
      state = state.copyWith(
        isSwitchingShift: false,
        error: "We couldn't start your shift. Check your signal and try again.",
      );
      _pubSub.disconnect();
      return;
    }

    _locationService ??= LocationService(pubSub: _pubSub);
    final result = await _locationService!.startReporting();

    // "While using the app" is not a failure — tracking starts — but it does
    // mean offers stop the moment the phone goes in a pocket, so it is
    // surfaced through the same channel as the hard failures.
    final issue = result.failure ??
        (result.foregroundOnly ? LocationStartFailure.backgroundDenied : null);

    state = state.copyWith(
      isOnline: true,
      isSwitchingShift: false,
      locationIssue: issue,
      clearLocationIssue: issue == null,
      locationForegroundOnly: result.foregroundOnly,
      error: result.started ? null : _locationErrorFor(result.failure),
    );
  }

  /// Go off shift. Refused while a delivery is in progress — the customer is
  /// waiting on food this driver is physically holding.
  ///
  /// Returns false, with [DeliveryFlowState.error] set to a plain-language
  /// explanation, when the request was refused.
  Future<bool> goOffline() async {
    if (state.hasActiveDelivery) {
      state = state.copyWith(
        error: 'Finish delivery #${state.activeOrderShortId ?? ''} first. '
            'Someone is waiting on this order.',
      );
      return false;
    }

    state = state.copyWith(isSwitchingShift: true, error: null, notice: null);

    // Decline anything on screen before the socket goes, so the order is
    // re-offered to another driver immediately rather than waiting out its
    // 45-second window.
    if (state.hasPendingOffer) {
      await declineOffer();
    }

    _pubSub.publishStatusChange('OFFLINE');
    _locationService?.stopReporting();
    _locationService = null;
    _pubSub.disconnect();

    try {
      await _apiClient.updateDashSession(active: false);
    } catch (e) {
      // The socket is already down and the driver has stopped being tracked,
      // so they are off shift whatever the server thinks. Do not block them.
      debugPrint('DeliveryNotifier: ending dash session failed: $e');
    }

    state = state.copyWith(
      isOnline: false,
      isSwitchingShift: false,
      offerExpired: false,
      clearOffer: true,
      deliveryState: DeliveryState.completed,
    );
    return true;
  }

  /// Retry the realtime link now, for the connection banner's Retry button.
  void reconnect() {
    final id = _driverId;
    if (id == null || id.isEmpty) return;
    if (_pubSub.isActive) {
      _pubSub.reconnectNow();
    } else {
      _pubSub.connect(id);
    }
  }

  // ── Offers ─────────────────────────────────────────────────────────────

  /// A new offer arrived. De-duplication and expiry filtering already happened
  /// in [PubSubService]; this decides whether the driver is free to see it.
  void receiveOffer(OrderOffer offer) {
    if (state.hasActiveDelivery) {
      debugPrint('DeliveryNotifier: offer ignored, delivery in progress');
      return;
    }
    if (state.hasPendingOffer && state.currentOffer?.orderId != offer.orderId) {
      // Dispatch offers one at a time, but a race can still land a second one.
      // Replacing the card mid-decision would be a great way to make a driver
      // accept the wrong job.
      debugPrint('DeliveryNotifier: offer ignored, one already on screen');
      return;
    }

    state = state.copyWith(
      currentOffer: offer,
      deliveryState: DeliveryState.offered,
      offerExpired: false,
      error: null,
      notice: null,
    );
    _startOfferTicker();
  }

  /// Drives the honest countdown: when the window closes the card is marked
  /// expired rather than silently failing on the next tap.
  void _startOfferTicker() {
    _offerTicker?.cancel();
    _offerTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final offer = state.currentOffer;
      if (!mounted ||
          offer == null ||
          state.deliveryState != DeliveryState.offered) {
        timer.cancel();
        return;
      }
      if (offer.isExpired && !state.offerExpired) {
        timer.cancel();
        // A timeout is *not* a decline. `POST /dispatch/decline` adds the
        // driver to the order's `declined_by` list, which permanently excludes
        // them from it being re-offered — punishing a driver for a card they
        // never got to. The server expires its own offers
        // (`clear_expired_offer`), so the app only has to stop lying about it.
        state = state.copyWith(
          offerExpired: true,
          notice: 'That offer ran out of time. Staying online for the next one.',
        );
      }
    });
  }

  /// Claim the offer on screen.
  ///
  /// Uses `POST /dispatch/accept`, which performs a conditional claim: exactly
  /// one of two drivers racing the same order wins and the loser gets a 409.
  /// Returns true when the job is now this driver's.
  Future<bool> acceptOffer() async {
    final offer = state.currentOffer;
    if (offer == null || state.isLoading) return false;

    if (offer.isExpired) {
      _offerTicker?.cancel();
      state = state.copyWith(
        offerExpired: true,
        notice: 'That offer ran out of time before it could be accepted.',
      );
      return false;
    }

    _offerTicker?.cancel();
    state = state.copyWith(isLoading: true, error: null, notice: null);

    try {
      await _apiClient.post('/dispatch/accept', data: {'order_id': offer.orderId});
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      state = state.copyWith(
        isLoading: false,
        deliveryState: DeliveryState.completed,
        clearOffer: true,
        offerExpired: false,
        // 409 is the documented "somebody else claimed it" answer. It is not a
        // failure by this driver and must not read like one.
        notice: status == 409
            ? 'Another driver got there first. No harm done — the next offer '
                'is on its way.'
            : null,
        error: status == 409
            ? null
            : (status == 400
                ? 'That order is no longer available.'
                : "We couldn't accept that offer. Check your signal and stay "
                    'online for the next one.'),
      );
      return false;
    } catch (e) {
      debugPrint('DeliveryNotifier: accept failed: $e');
      state = state.copyWith(
        isLoading: false,
        deliveryState: DeliveryState.completed,
        clearOffer: true,
        error: "We couldn't accept that offer. Check your signal and stay "
            'online for the next one.',
      );
      return false;
    }

    // Keep the offer: it is now the job, and every screen downstream needs its
    // addresses and coordinates.
    state = state.copyWith(
      deliveryState: DeliveryState.enRoutePickup,
      currentOffer: offer,
      activeOrderId: offer.orderId,
      activeOrderShortId: offer.shortId,
      earningsCents: offer.payoutCents(),
      isLoading: false,
      offerExpired: false,
      error: null,
      notice: null,
    );
    return true;
  }

  /// Turn down the offer on screen so dispatch moves it to the next driver
  /// immediately.
  Future<void> declineOffer() async {
    final offer = state.currentOffer;
    _offerTicker?.cancel();

    state = state.copyWith(
      deliveryState: DeliveryState.completed,
      clearOffer: true,
      offerExpired: false,
      isLoading: false,
      error: null,
      notice: null,
    );

    if (offer == null) return;
    try {
      await _apiClient
          .post('/dispatch/decline', data: {'order_id': offer.orderId});
    } catch (e) {
      // The order still times out server-side and is re-offered, so a failed
      // decline costs the next driver a few seconds, not the order. Nothing
      // worth interrupting this driver over.
      debugPrint('DeliveryNotifier: decline failed: $e');
      _pubSub.publishDecline(offer.orderId);
    }
  }

  /// Dismiss the expired card and go back to waiting for work.
  void dismissExpiredOffer() {
    _offerTicker?.cancel();
    state = state.copyWith(
      deliveryState: DeliveryState.completed,
      clearOffer: true,
      offerExpired: false,
      error: null,
      notice: null,
    );
  }

  // ── Delivery progress ──────────────────────────────────────────────────

  /// Advance the delivery one step and tell the backend.
  ///
  /// REST first, because `PUT /orders/{id}/state` validates the transition and
  /// answers; the socket is the fallback for when REST cannot get through, so
  /// a driver in a signal dead-spot still moves forward locally and the server
  /// catches up. Local state advances either way — a driver standing at a
  /// restaurant must never be blocked by a flaky connection.
  Future<void> transitionTo(DeliveryState next) async {
    if (!state.deliveryState.canTransitionTo(next)) return;

    state = state.copyWith(deliveryState: next, error: null, notice: null);

    final backendState = next.backendState;
    final orderId = state.activeOrderId;
    if (backendState == null || orderId == null) return;

    try {
      await _apiClient.put('/orders/$orderId/state', data: {'state': backendState});
    } catch (e) {
      debugPrint('DeliveryNotifier: state sync failed ($backendState): $e');
      // Best effort over the socket. If that is down too, `/dispatch/state`
      // reconciles on the next launch.
      _pubSub.publishDeliveryAction(orderId, backendState);
    }
  }

  /// Confirm the food is in the driver's hands.
  ///
  /// This is the step that reports `PICKED_UP`, which is also the point of no
  /// return: after it the backend will not hand the order back to dispatch.
  Future<void> confirmPickup() => transitionTo(DeliveryState.pickedUp);

  /// Hand the order back before pickup so dispatch can re-offer it.
  ///
  /// Only possible before collection — `POST /dispatch/release` refuses once
  /// the driver physically holds the food, and answers with a message saying
  /// to contact support instead.
  Future<bool> releaseOrder() async {
    final orderId = state.activeOrderId;
    if (orderId == null) return false;
    if (state.deliveryState.hasCollectedOrder) {
      state = state.copyWith(
        error: 'You already collected this order, so it cannot be handed back. '
            'Contact support.',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, error: null, notice: null);
    try {
      await _apiClient.post('/dispatch/release', data: {'order_id': orderId});
    } catch (e) {
      debugPrint('DeliveryNotifier: release failed: $e');
      state = state.copyWith(
        isLoading: false,
        error: "We couldn't hand that order back. Check your signal and try "
            'again, or contact support.',
      );
      return false;
    }

    state = state.copyWith(
      deliveryState: DeliveryState.completed,
      clearActiveOrder: true,
      clearOffer: true,
      isLoading: false,
      notice: 'Order handed back. It is going to another driver now.',
    );
    return true;
  }

  /// Close out the delivery.
  ///
  /// `POST /dispatch/complete` moves the order to `DELIVERED` through the state
  /// machine with `require_driver_id`, so it is audited, the consumer is
  /// notified, and it is refused unless *this* driver actually collected it.
  ///
  /// Nothing is cleared until the server has accepted, because a driver whose
  /// completion silently failed would lose the job from their screen and never
  /// be paid for it. Returns true when the delivery is done.
  Future<bool> completeDelivery() async {
    final orderId = state.activeOrderId;
    if (orderId == null || state.isLoading) return false;

    state = state.copyWith(isLoading: true, error: null, notice: null);

    try {
      await _apiClient.post('/dispatch/complete', data: {'order_id': orderId});
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      state = state.copyWith(
        isLoading: false,
        error: switch (status) {
          409 => 'This order changed while you were finishing up. Pull to '
              'refresh, or contact support if the customer has their food.',
          400 => "The order isn't ready to be completed yet. Confirm you "
              'collected it first.',
          404 => 'We could not find that order. Contact support.',
          _ => "We couldn't mark this delivered. Check your signal and try "
              'again — your delivery is safe.',
        },
      );
      return false;
    } catch (e) {
      debugPrint('DeliveryNotifier: complete failed: $e');
      state = state.copyWith(
        isLoading: false,
        error: "We couldn't mark this delivered. Check your signal and try "
            'again — your delivery is safe.',
      );
      return false;
    }

    // Book the earning. A failure here is a finance problem, not a delivery
    // problem: the order is delivered and the ledger can be reconciled, so the
    // driver is not held on this screen for it.
    final driverId = _driverId;
    if (driverId != null) {
      try {
        final response = await _apiClient.recordEarning(
          orderId: orderId,
          driverId: driverId,
        );
        final total = (response.data?['total_earning_cents'] as num?)?.toInt();
        if (total != null) {
          state = state.copyWith(earningsCents: total);
        }
      } catch (e) {
        debugPrint('DeliveryNotifier: recording earning failed: $e');
      }
    }

    state = state.copyWith(
      deliveryState: DeliveryState.completed,
      clearActiveOrder: true,
      clearOffer: true,
      isLoading: false,
      offerExpired: false,
      error: null,
      notice: null,
    );
    return true;
  }

  // ── Server pushes ──────────────────────────────────────────────────────

  void _onOrderUpdate(String orderId, String orderState) {
    if (state.activeOrderId != orderId) return;

    if (orderState == 'CANCELLED') {
      state = state.copyWith(
        deliveryState: DeliveryState.completed,
        clearActiveOrder: true,
        clearOffer: true,
        notice: 'This order was cancelled. You are back online for new offers.',
      );
      return;
    }

    final next = DeliveryState.fromBackendState(orderState);
    // Only follow the server *forward*. A late-arriving push for a step the
    // driver has already passed must not drag them back a screen.
    if (next != DeliveryState.completed &&
        DeliveryState.values.indexOf(next) >
            DeliveryState.values.indexOf(state.deliveryState)) {
      state = state.copyWith(deliveryState: next);
    }
  }

  /// The backend refused something over the socket.
  void _onPubSubError(PubSubError error) {
    debugPrint('DeliveryNotifier: $error');
    switch (error.code) {
      case PubSubErrorCode.offerUnavailable:
        if (state.currentOffer?.orderId != error.orderId) return;
        _offerTicker?.cancel();
        state = state.copyWith(
          deliveryState: DeliveryState.completed,
          clearOffer: true,
          offerExpired: false,
          isLoading: false,
          notice: 'Another driver got there first. No harm done — the next '
              'offer is on its way.',
        );
      case PubSubErrorCode.deliveryActionRejected:
      case PubSubErrorCode.unknown:
        // Nothing to undo locally: the REST path is authoritative for every
        // state change, and `/dispatch/state` reconciles on next launch.
        break;
    }
  }

  // ── Resume ─────────────────────────────────────────────────────────────

  /// Restore the shift and any job in progress from the backend.
  ///
  /// Called on app launch. The `active_order` payload carries the pickup and
  /// drop-off points, which are rebuilt into an [OrderOffer] so the navigation
  /// screens have somewhere real to send the driver.
  Future<void> fetchCurrentState(String userId) async {
    if (userId.isEmpty) return;
    _driverId = userId;

    Map<String, dynamic> data;
    try {
      final response = await _apiClient.get('/dispatch/state');
      final body = response.data;
      if (body is! Map<String, dynamic>) return;
      data = body;
    } catch (e) {
      debugPrint('DeliveryNotifier: fetching driver state failed: $e');
      return;
    }

    if (data['status'] == 'ONLINE' && !state.isOnline) {
      await goOnline(userId);
    }

    final activeOrder = data['active_order'];
    if (activeOrder is! Map<String, dynamic>) return;

    final restored = OrderOffer.fromDispatchState(activeOrder);
    if (restored == null) return;

    final deliveryState =
        DeliveryState.fromBackendState(activeOrder['state'] as String?);
    if (deliveryState == DeliveryState.completed) return;

    state = state.copyWith(
      deliveryState: deliveryState,
      currentOffer: restored,
      activeOrderId: restored.orderId,
      activeOrderShortId: restored.shortId,
      earningsCents: restored.deliveryFeeCents > 0
          ? restored.payoutCents()
          : state.earningsCents,
      isLoading: false,
    );
  }

  /// Clear the transient error / notice after the UI has shown it.
  void clearMessages() {
    if (state.error == null && state.notice == null) return;
    state = state.copyWith(error: null, notice: null);
  }

  /// Ask the OS to open this app's settings page, for a permanently denied
  /// location permission.
  Future<void> openLocationSettings() async {
    final service = _locationService ?? LocationService(pubSub: _pubSub);
    if (state.locationIssue == LocationStartFailure.serviceDisabled) {
      await service.openLocationSettings();
    } else {
      await service.openPermissionSettings();
    }
  }

  /// Hand every stuck order back to dispatch or complete it, then reset.
  ///
  /// `POST /dispatch/reset` is state-aware server-side: orders the driver
  /// collected are completed through the state machine, orders they had merely
  /// accepted are released and re-offered.
  Future<void> resetToIdle() async {
    _offerTicker?.cancel();
    state = state.copyWith(isLoading: true, error: null, notice: null);
    try {
      final response = await _apiClient.post('/dispatch/reset');
      final message = response.data?['message'] as String?;
      state = DeliveryFlowState(
        isOnline: state.isOnline,
        connectionStatus: state.connectionStatus,
        connectionMessage: state.connectionMessage,
        notice: message ?? 'Your deliveries have been cleared.',
      );
    } catch (e) {
      debugPrint('DeliveryNotifier: reset failed: $e');
      state = state.copyWith(
        isLoading: false,
        error: "We couldn't clear your deliveries. Check your signal and try "
            'again.',
      );
    }
  }

  String? _locationErrorFor(LocationStartFailure? failure) => switch (failure) {
        LocationStartFailure.serviceDisabled =>
          'Turn on location on your phone — dispatch cannot send you orders '
              'without it.',
        LocationStartFailure.denied =>
          'Zvingo needs your location to send you nearby orders. Allow it to '
              'start earning.',
        LocationStartFailure.deniedForever =>
          'Location is blocked for Zvingo. Open Settings and allow it, or you '
              "won't receive any orders.",
        LocationStartFailure.backgroundDenied =>
          'Set location to "Allow all the time" so you keep getting offers '
              'with your screen off.',
        null => null,
      };

  @override
  void dispose() {
    _offerTicker?.cancel();
    _statusSub?.cancel();
    _locationService?.dispose();
    _pubSub.dispose();
    super.dispose();
  }
}

/// The delivery flow.
final deliveryProvider =
    StateNotifierProvider<DeliveryNotifier, DeliveryFlowState>((ref) {
  return DeliveryNotifier(ref.read(apiClientProvider));
});

/// Realtime link state, for `ConnectionStatusBanner`.
///
/// This is the provider `widgets/connection_status_banner.dart` documents but
/// could not have: `PubSubService` exposed no connection state, so the banner
/// shipped unwired. It now mirrors the socket's own status stream.
final connectionStatusProvider = Provider<ConnectionStatus>((ref) {
  return ref.watch(deliveryProvider.select((s) => s.connectionStatus));
});

/// Plain-language detail for [connectionStatusProvider], or null.
final connectionMessageProvider = Provider<String?>((ref) {
  return ref.watch(deliveryProvider.select((s) => s.connectionMessage));
});

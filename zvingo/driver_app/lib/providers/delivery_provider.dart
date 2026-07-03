import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../core/api_client.dart';
import '../models/delivery_state.dart';
import '../models/order_offer.dart';
import '../services/pub_sub_service.dart';
import '../services/location_service.dart';

/// Delivery flow state.
class DeliveryFlowState {
  final DeliveryState deliveryState;
  final OrderOffer? currentOffer;
  final String? activeOrderId;
  final String? activeOrderShortId;
  final bool isLoading;
  final String? error;
  final int? earningsCents;

  const DeliveryFlowState({
    this.deliveryState = DeliveryState.completed,
    this.currentOffer,
    this.activeOrderId,
    this.activeOrderShortId,
    this.isLoading = false,
    this.error,
    this.earningsCents,
  });

  bool get hasActiveDelivery => deliveryState != DeliveryState.completed;

  DeliveryFlowState copyWith({
    DeliveryState? deliveryState,
    OrderOffer? currentOffer,
    bool clearOffer = false,
    String? activeOrderId,
    bool clearActiveOrder = false,
    String? activeOrderShortId,
    bool? isLoading,
    String? error,
    int? earningsCents,
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
      error: error,
      earningsCents: earningsCents ?? this.earningsCents,
    );
  }
}

/// Delivery provider — manages real-time offers via WebSocket pub/sub,
/// location reporting, and backend API calls for accept/decline.
class DeliveryNotifier extends StateNotifier<DeliveryFlowState> {
  final ApiClient _apiClient;
  Timer? _offerTimeout;
  String? _driverId;

  // Single WebSocket pub/sub service (replaces SSE + HTTP location calls)
  final PubSubService _pubSub = PubSubService();
  LocationService? _locationService;

  DeliveryNotifier(this._apiClient) : super(const DeliveryFlowState());

  /// Start listening for offers and reporting location.
  /// Safe to call multiple times — PubSubService handles dedup internally.
  Future<void> goOnline(String userId) async {
    _driverId = userId;
    // 1. Connect WebSocket FIRST so the Redis subscription is in place
    //    before the driver is marked ONLINE and becomes dispatchable.
    //    The backend also caches any offer published in this window and
    //    flushes it on connect, but subscribing first minimises the gap.
    _pubSub.onOffer = receiveOffer;
    _pubSub.onOrderUpdate = _onOrderUpdate;
    _pubSub.connect(userId);

    // 2. Get GPS + register ONLINE in backend/Redis (now WS is subscribing)
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _apiClient.updateDashSession(
        active: true,
        lat: position.latitude,
        lng: position.longitude,
        radius: 10,
      );
    } catch (e) {
      debugPrint('Error getting location for dash start: $e');
    }

    // 3. Location: report GPS via pub/sub (only create if not already reporting)
    if (_locationService == null) {
      _locationService = LocationService(pubSub: _pubSub);
      final granted = await _locationService!.startReporting();
      if (!granted) {
        // Surface the permission failure so the driver knows they won't get orders
        state = state.copyWith(
          error: 'Location permission denied. Enable it in Settings to receive orders.',
        );
        debugPrint('DeliveryNotifier: Location permission not granted');
      }
    }
  }

  /// Stop listening and reporting.
  Future<void> goOffline() async {
    _pubSub.publishStatusChange('OFFLINE');
    _pubSub.disconnect();
    _locationService?.stopReporting();
    _locationService = null;

    // End Dash Session on backend
    try {
      await _apiClient.updateDashSession(active: false);
    } catch (e) {
      debugPrint('Error ending dash session: $e');
    }
  }

  /// Receive a real offer from the pub/sub stream (or simulated).
  void receiveOffer(OrderOffer offer) {
    debugPrint('DeliveryNotifier: receiveOffer called for ${offer.orderId}');
    debugPrint('DeliveryNotifier: hasActiveDelivery=${state.hasActiveDelivery}, currentState=${state.deliveryState}');
    if (state.hasActiveDelivery) {
      debugPrint('DeliveryNotifier: SKIPPING offer - already has active delivery');
      return;
    }

    debugPrint('DeliveryNotifier: Setting state to OFFERED with offer ${offer.shortId}');
    state = state.copyWith(
      currentOffer: offer,
      deliveryState: DeliveryState.offered,
    );

    _offerTimeout?.cancel();
    _offerTimeout = Timer(Duration(seconds: offer.timeoutSeconds), () {
      if (state.deliveryState == DeliveryState.offered) {
        declineOffer();
      }
    });
  }

  void _onOrderUpdate(String orderId, String orderState) {
    debugPrint('DeliveryNotifier: Order update $orderId → $orderState');
    // Map backend state string to local DeliveryState if the active order matches
    if (state.activeOrderId == orderId) {
      final deliveryState = _mapStringToDeliveryState(orderState);
      state = state.copyWith(deliveryState: deliveryState);
    }
  }

  /// Accept the current offer — published via WebSocket, no separate HTTP call.
  Future<void> acceptOffer() async {
    final offer = state.currentOffer;
    if (offer == null) return;
    if (!state.deliveryState.canTransitionTo(DeliveryState.accepted)) return;

    _offerTimeout?.cancel();
    state = state.copyWith(isLoading: true);

    try {
      _pubSub.publishAccept(offer.orderId);

      state = state.copyWith(
        deliveryState: DeliveryState.accepted,
        activeOrderId: offer.orderId,
        activeOrderShortId: offer.shortId,
        clearOffer: true,
        isLoading: false,
        earningsCents: offer.deliveryFeeCents,
      );
      // Auto-transition to en route
      transitionTo(DeliveryState.enRoutePickup);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to accept offer',
      );
    }
  }

  /// Decline the current offer — published via WebSocket.
  Future<void> declineOffer() async {
    final offer = state.currentOffer;
    _offerTimeout?.cancel();

    if (offer != null) {
      _pubSub.publishDecline(offer.orderId);
    }

    state = state.copyWith(
      deliveryState: DeliveryState.completed,
      clearOffer: true,
    );
  }

  /// Transition to the next delivery state and sync to backend where applicable.
  void transitionTo(DeliveryState next) {
    if (!state.deliveryState.canTransitionTo(next)) return;
    state = state.copyWith(deliveryState: next);

    final backendState = next.backendState;
    final orderId = state.activeOrderId;
    if (backendState != null && orderId != null) {
      _pubSub.publishDeliveryAction(orderId, backendState);
      debugPrint('DeliveryNotifier: syncing $next → backend $backendState for order $orderId');
    }
  }

  /// Complete delivery with PIN + optional cash.
  Future<void> completeDelivery({required String pin, int cashCollectedCents = 0}) async {
    // Capture order info before clearing state
    final orderId = state.activeOrderId;

    // Reset local state immediately so the UI responds without waiting for the network.
    state = state.copyWith(
      deliveryState: DeliveryState.completed,
      clearActiveOrder: true,
      clearOffer: true,
    );

    // Tell the backend the order is done so fetchCurrentState() won't restore
    // a stale active order on the next app launch.
    try {
      await _apiClient.post('/dispatch/reset');
      debugPrint('DeliveryNotifier: Backend order marked DELIVERED');
    } catch (e) {
      debugPrint('DeliveryNotifier: Failed to mark delivery complete on backend: $e');
    }

    // Record the earning in the ledger
    if (orderId != null && _driverId != null) {
      try {
        final response = await _apiClient.recordEarning(
          orderId: orderId,
          driverId: _driverId!,
        );
        final data = response.data;
        debugPrint('DeliveryNotifier: Earning recorded — total=${data['total_earning_cents']}c');
      } catch (e) {
        debugPrint('DeliveryNotifier: Failed to record earning: $e');
      }
    }
  }

  /// Inject a simulated offer for dev testing.
  void simulateOffer() {
    receiveOffer(OrderOffer(
      orderId: 'order-${DateTime.now().millisecondsSinceEpoch}',
      shortId: 'ZV${DateTime.now().millisecondsSinceEpoch % 10000}',
      merchantName: 'Chicken Inn Samora',
      merchantAddress: '2 Samora Machel Ave, Harare',
      pickupLat: -17.8216,
      pickupLng: 31.0492,
      customerName: 'Tinashe M.',
      customerAddress: '14 Selous Ave, Harare',
      deliveryLat: -17.8248,
      deliveryLng: 31.0530,
      deliveryFeeCents: 350,
      estimatedDistanceKm: 3.2,
      pickupDistanceKm: 1.1,
      estimatedTimeMinutes: 18,
      pickupTimeMinutes: 5,
      itemsSummary: '2pc Chicken Meal +1 more',
      itemCount: 3,
      paymentMethod: PaymentMethod.cash,
    ));
  }

  /// Initial check: get state from backend (active order? online?)
  Future<void> fetchCurrentState(String userId) async {
    _driverId = userId;
    try {
      final response = await _apiClient.get('/dispatch/state');
      final data = response.data;

      final status = data['status'];
      final activeOrder = data['active_order'];

      // 1. Restore online status
      if (status == 'ONLINE') {
        await goOnline(userId);
      }

      // 2. Restore active order
      if (activeOrder != null) {
        final orderId = activeOrder['order_id'];
        final stateStr = activeOrder['state'];

        final deliveryState = _mapStringToDeliveryState(stateStr);

        state = state.copyWith(
          deliveryState: deliveryState,
          activeOrderId: orderId,
          activeOrderShortId: activeOrder['short_id'] ?? 'RESTORED',
          isLoading: false,
        );
      }
    } catch (e) {
      debugPrint('Error fetching driver state: $e');
    }
  }

  DeliveryState _mapStringToDeliveryState(String status) {
    switch (status) {
      case 'ACCEPTED': return DeliveryState.enRoutePickup;
      case 'ARRIVED_AT_MERCHANT': return DeliveryState.arrivedPickup;
      case 'PICKED_UP': return DeliveryState.enRouteDelivery;
      case 'ARRIVED_AT_CUSTOMER': return DeliveryState.arrivedDelivery;
      case 'DELIVERED': return DeliveryState.delivered;
      default: return DeliveryState.completed;
    }
  }

  /// Force reset to idle state (for debugging stale state issues)
  /// Also calls backend to reset any stuck orders.
  Future<void> resetToIdle() async {
    debugPrint('DeliveryNotifier: FORCE RESET to idle state');
    _offerTimeout?.cancel();
    
    // Call backend to reset any stuck orders
    try {
      await _apiClient.post('/dispatch/reset');
      debugPrint('DeliveryNotifier: Backend reset successful');
    } catch (e) {
      debugPrint('DeliveryNotifier: Backend reset failed: $e');
    }
    
    state = const DeliveryFlowState();
  }

  @override
  void dispose() {
    _offerTimeout?.cancel();
    _pubSub.disconnect();
    _locationService?.dispose();
    super.dispose();
  }
}

/// Global delivery provider.
final deliveryProvider =
    StateNotifierProvider<DeliveryNotifier, DeliveryFlowState>((ref) {
  return DeliveryNotifier(ref.read(apiClientProvider));
});

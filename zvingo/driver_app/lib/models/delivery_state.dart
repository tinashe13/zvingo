/// Delivery state machine — mirrors DeliveryState.kt.
/// Full lifecycle: OFFERED → ACCEPTED → EN_ROUTE_PICKUP → ARRIVED_PICKUP
/// → PICKED_UP → EN_ROUTE_DELIVERY → ARRIVED_DELIVERY → DELIVERED → COMPLETED
enum DeliveryState {
  offered,
  accepted,
  enRoutePickup,
  arrivedPickup,
  pickedUp,
  enRouteDelivery,
  arrivedDelivery,
  delivered,
  completed;

  /// Valid transitions from this state.
  Set<DeliveryState> get validTransitions => switch (this) {
        offered => {accepted, completed},
        accepted => {enRoutePickup, completed},
        enRoutePickup => {arrivedPickup, completed},
        arrivedPickup => {pickedUp, completed},
        pickedUp => {enRouteDelivery, completed},
        enRouteDelivery => {arrivedDelivery, completed},
        arrivedDelivery => {delivered, completed},
        delivered => {completed},
        completed => {},
      };

  bool canTransitionTo(DeliveryState next) => validTransitions.contains(next);
  bool get isTerminal => this == completed;
  bool get isActive => this != offered && this != completed;

  /// Sync action string sent to backend.
  String? get syncAction => switch (this) {
        enRoutePickup => 'en_route_pickup',
        arrivedPickup => 'arrived_pickup',
        pickedUp => 'picked_up',
        enRouteDelivery => 'en_route_delivery',
        arrivedDelivery => 'arrived_delivery',
        delivered => 'delivered',
        _ => null,
      };

  /// Backend OrderState string for this Flutter state, sent via WebSocket
  /// `delivery_action` messages. Null means no backend transition is needed
  /// (e.g. `pickedUp` is a UI-only state; `enRoutePickup` is already covered
  /// by the initial accept_offer message).
  String? get backendState => switch (this) {
        arrivedPickup => 'ARRIVED_AT_MERCHANT',
        enRouteDelivery => 'PICKED_UP',
        arrivedDelivery => 'ARRIVED_AT_CUSTOMER',
        delivered => 'DELIVERED',
        _ => null,
      };
}

/// Where the driver is in one delivery.
///
/// Full lifecycle:
/// `offered → accepted → enRoutePickup → arrivedPickup → pickedUp →
///  enRouteDelivery → arrivedDelivery → delivered → completed`
///
/// This mirrors, but is not identical to, the backend's `OrderState`
/// (`backend/app/order/state_machine.py`). The app has UI-only steps the
/// server does not model — [accepted] and [pickedUp] are screens, not order
/// states — so [backendState] is the single place the two vocabularies are
/// reconciled. Nothing else in the app should map these strings by hand.
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

  /// True while the driver is actually carrying out a job. A pending offer is
  /// deliberately excluded — a card on screen is not a commitment, and
  /// blocking "go offline" on it would be wrong.
  bool get isActive => this != offered && this != completed;

  /// True once the food is physically in the driver's hands. After this point
  /// the order cannot be handed back to dispatch (the backend's
  /// `RELEASABLE_STATES` stops at pickup), which changes what the app is
  /// allowed to offer the driver.
  bool get hasCollectedOrder =>
      this == pickedUp || this == enRouteDelivery ||
      this == arrivedDelivery || this == delivered;

  /// One-line answer to "where am I going?", for headers and the shell bar.
  String get destinationHeadline => switch (this) {
        offered => 'New offer',
        accepted || enRoutePickup => 'Ride to the restaurant',
        arrivedPickup => 'Collect the order',
        pickedUp => 'Order collected',
        enRouteDelivery => 'Ride to the customer',
        arrivedDelivery => 'Hand over the order',
        delivered => 'Finish up',
        completed => 'No active delivery',
      };

  /// Sync action string used by the offline sync queue.
  String? get syncAction => switch (this) {
        enRoutePickup => 'en_route_pickup',
        arrivedPickup => 'arrived_pickup',
        pickedUp => 'picked_up',
        enRouteDelivery => 'en_route_delivery',
        arrivedDelivery => 'arrived_delivery',
        delivered => 'delivered',
        _ => null,
      };

  /// The backend `OrderState` this step reports, or null when the step is
  /// UI-only and the server already knows where the order is.
  ///
  /// * [accepted] / [enRoutePickup] — the server set `ACCEPTED` itself when it
  ///   granted the claim, so re-reporting it would be a no-op transition the
  ///   state machine rejects.
  /// * [pickedUp] — this is the step where the driver confirms they have the
  ///   food, so this is where `PICKED_UP` belongs. It used to be reported one
  ///   step later, from [enRouteDelivery], which meant that a driver who
  ///   collected an order and then closed the app was still recorded as
  ///   standing empty-handed at the restaurant.
  /// * [delivered] — reported through `POST /dispatch/complete` rather than
  ///   the socket, because completion needs a synchronous answer before the
  ///   app clears the job.
  String? get backendState => switch (this) {
        arrivedPickup => 'ARRIVED_AT_MERCHANT',
        pickedUp => 'PICKED_UP',
        arrivedDelivery => 'ARRIVED_AT_CUSTOMER',
        _ => null,
      };

  /// The app step that corresponds to a backend `OrderState`. Used to resume a
  /// delivery after a restart and to follow `order_update` pushes.
  static DeliveryState fromBackendState(String? state) => switch (state) {
        'ACCEPTED' => DeliveryState.enRoutePickup,
        'ARRIVED_AT_MERCHANT' || 'READY_FOR_PICKUP' =>
          DeliveryState.arrivedPickup,
        'PICKED_UP' => DeliveryState.enRouteDelivery,
        'ARRIVED_AT_CUSTOMER' => DeliveryState.arrivedDelivery,
        'DELIVERED' || 'CANCELLED' => DeliveryState.completed,
        _ => DeliveryState.completed,
      };
}

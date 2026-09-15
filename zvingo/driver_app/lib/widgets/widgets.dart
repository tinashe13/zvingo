/// The Zvingo driver widget library.
///
/// One import gives a feature screen the whole shared component set:
///
/// ```dart
/// import '../../widgets/widgets.dart';
/// ```
///
/// Everything here conforms to `docs/DESIGN_SYSTEM.md` and to the driver
/// ergonomics recorded in `core/theme.dart`: 56pt actions, ≥15pt actionable
/// text, high-contrast figure/ground, and slide-to-confirm for anything
/// irreversible.
library;

// `StaggeredEntrance` is the §4.3 list-entrance widget. It lives with the
// motion tokens it implements, but feature screens reach for it alongside the
// rest of the library, so it is re-exported here.
export '../core/app_motion.dart' show StaggeredEntrance;
export 'active_delivery_bar.dart';
export 'animated_count.dart';
export 'confirm_sheet.dart';
export 'connection_status_banner.dart';
export 'delivery_step_indicator.dart';
export 'driver_app_bar.dart';
export 'driver_buttons.dart';
export 'driver_states.dart';
export 'floating_map_button.dart';
export 'navigation_map.dart';
export 'offer_card.dart';
export 'online_offline_toggle.dart';
export 'skeletons.dart';
export 'slide_to_confirm.dart';
export 'status_chip.dart';
export 'tap_scale.dart';
export 'map_attribution.dart';

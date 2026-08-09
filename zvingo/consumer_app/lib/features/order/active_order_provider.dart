import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the ID of the current active order to show in the bottom sheet.
/// If null, no order is being tracked in the overlay.
final activeOrderProvider = StateProvider<String?>((ref) => null);

import 'package:hive/hive.dart';

part 'saved_address.g.dart';

/// A delivery address the customer has saved.
///
/// Fields 6 and 7 were added after the first release. Hive returns `null` for a
/// field an older record never wrote, so both are nullable and both default to
/// empty — an existing box keeps reading without a migration.
@HiveType(typeId: 1)
class SavedAddress extends HiveObject {
  @HiveField(0)
  final String id;

  /// "Home", "Work", or whatever the customer typed.
  @HiveField(1)
  final String label;

  /// Full display address, as geocoded or as the customer corrected it.
  @HiveField(2)
  final String address;

  @HiveField(3)
  final double lat;

  @HiveField(4)
  final double lng;

  @HiveField(5)
  final bool isDefault;

  /// What the driver should do on arrival: "Gate is on Chiremba Rd, ring twice."
  ///
  /// This is the single biggest determinant of whether food actually arrives,
  /// so it is a first-class field rather than something squeezed into [address].
  @HiveField(6)
  final String? instructions;

  /// How to get in: flat number, building name, security code, floor.
  @HiveField(7)
  final String? accessNote;

  SavedAddress({
    required this.id,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    this.isDefault = false,
    this.instructions,
    this.accessNote,
  });

  /// True when the customer has told the driver something useful.
  bool get hasDeliveryNotes =>
      (instructions != null && instructions!.trim().isNotEmpty) ||
      (accessNote != null && accessNote!.trim().isNotEmpty);

  /// The note line shown under the address on cards and sheets.
  String get notesSummary {
    final parts = <String>[
      if (accessNote != null && accessNote!.trim().isNotEmpty)
        accessNote!.trim(),
      if (instructions != null && instructions!.trim().isNotEmpty)
        instructions!.trim(),
    ];
    return parts.join(' · ');
  }

  SavedAddress copyWith({
    String? id,
    String? label,
    String? address,
    double? lat,
    double? lng,
    bool? isDefault,
    String? instructions,
    String? accessNote,
  }) {
    return SavedAddress(
      id: id ?? this.id,
      label: label ?? this.label,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      isDefault: isDefault ?? this.isDefault,
      instructions: instructions ?? this.instructions,
      accessNote: accessNote ?? this.accessNote,
    );
  }
}

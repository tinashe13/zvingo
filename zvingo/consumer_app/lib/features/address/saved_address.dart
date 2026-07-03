import 'package:hive/hive.dart';

part 'saved_address.g.dart';

@HiveType(typeId: 1)
class SavedAddress extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String label; // e.g. "Home", "Work", "Other"

  @HiveField(2)
  final String address; // Full display address

  @HiveField(3)
  final double lat;

  @HiveField(4)
  final double lng;

  @HiveField(5)
  final bool isDefault;

  SavedAddress({
    required this.id,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    this.isDefault = false,
  });

  SavedAddress copyWith({
    String? id,
    String? label,
    String? address,
    double? lat,
    double? lng,
    bool? isDefault,
  }) {
    return SavedAddress(
      id: id ?? this.id,
      label: label ?? this.label,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

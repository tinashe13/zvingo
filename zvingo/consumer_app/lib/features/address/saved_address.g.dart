// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_address.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedAddressAdapter extends TypeAdapter<SavedAddress> {
  @override
  final int typeId = 1;

  @override
  SavedAddress read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedAddress(
      id: fields[0] as String,
      label: fields[1] as String,
      address: fields[2] as String,
      lat: fields[3] as double,
      lng: fields[4] as double,
      isDefault: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SavedAddress obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.address)
      ..writeByte(3)
      ..write(obj.lat)
      ..writeByte(4)
      ..write(obj.lng)
      ..writeByte(5)
      ..write(obj.isDefault);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedAddressAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

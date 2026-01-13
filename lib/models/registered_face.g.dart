// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registered_face.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RegisteredFaceAdapter extends TypeAdapter<RegisteredFace> {
  @override
  final int typeId = 1;

  @override
  RegisteredFace read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RegisteredFace(
      id: fields[0] as String,
      name: fields[1] as String,
      relationship: fields[2] as String,
      embedding: (fields[3] as List).cast<double>(),
      registeredAt: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, RegisteredFace obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.relationship)
      ..writeByte(3)
      ..write(obj.embedding)
      ..writeByte(4)
      ..write(obj.registeredAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredFaceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

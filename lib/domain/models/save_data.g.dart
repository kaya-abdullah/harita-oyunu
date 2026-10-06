// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_data.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SaveDataAdapter extends TypeAdapter<SaveData> {
  @override
  final int typeId = 0;

  @override
  SaveData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SaveData(
      territoriesJson: fields[0] as String,
      armiesJson: fields[1] as String,
      currentTurn: fields[3] as int,
      activeArmyId: fields[4] as String,
      phase: fields[5] as String,
      schemaVersion: fields[7] as int,
      winnerId: fields[6] as String?,
      difficulty: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SaveData obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.territoriesJson)
      ..writeByte(1)
      ..write(obj.armiesJson)
      ..writeByte(3)
      ..write(obj.currentTurn)
      ..writeByte(4)
      ..write(obj.activeArmyId)
      ..writeByte(5)
      ..write(obj.phase)
      ..writeByte(6)
      ..write(obj.winnerId)
      ..writeByte(7)
      ..write(obj.schemaVersion)
      ..writeByte(8)
      ..write(obj.difficulty);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaveDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

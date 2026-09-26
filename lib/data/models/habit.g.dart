// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HabitAdapter extends TypeAdapter<Habit> {
  @override
  final typeId = 0;

  @override
  Habit read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Habit(
      id: fields[0] as String,
      title: fields[1] as String,
      totalDays: (fields[2] as num).toInt(),
      startDate: fields[3] as DateTime,
      colorValue: (fields[4] as num).toInt(),
      createdAt: fields[5] as DateTime?,
      completedDays: (fields[6] as List?)?.cast<int>(),
      archived: fields[7] == null ? false : fields[7] as bool,
      isFixed: fields[8] == null ? false : fields[8] as bool,
      reminderTimes: (fields[9] as List?)?.cast<int>(),
      isPaused: fields[10] == null ? false : fields[10] as bool,
      pausedAt: fields[11] as DateTime?,
      isBad: fields[12] == null ? false : fields[12] as bool,
      slipDays: fields[13] == null ? [] : (fields[13] as List?)?.cast<int>(),
      isStrict: fields[14] == null ? false : fields[14] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Habit obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.totalDays)
      ..writeByte(3)
      ..write(obj.startDate)
      ..writeByte(4)
      ..write(obj.colorValue)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.completedDays)
      ..writeByte(7)
      ..write(obj.archived)
      ..writeByte(8)
      ..write(obj.isFixed)
      ..writeByte(9)
      ..write(obj.reminderTimes)
      ..writeByte(10)
      ..write(obj.isPaused)
      ..writeByte(11)
      ..write(obj.pausedAt)
      ..writeByte(12)
      ..write(obj.isBad)
      ..writeByte(13)
      ..write(obj.slipDays)
      ..writeByte(14)
      ..write(obj.isStrict);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HabitAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

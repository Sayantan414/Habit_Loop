import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/habit.dart';

/// Thin wrapper around the Hive box that stores [Habit]s.
class HabitRepository {
  HabitRepository(this._box);

  static const boxName = 'habits';

  final Box<Habit> _box;

  List<Habit> getAll() => _box.values.toList(growable: false);

  Habit? getById(String id) {
    try {
      return _box.values.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> add(Habit habit) => _box.put(habit.id, habit);

  Future<void> update(Habit habit) => habit.save();

  Future<void> delete(String id) => _box.delete(id);

  Future<void> toggleDay(Habit habit, int dayNumber) async {
    final done = habit.completedDays.toList();
    if (done.contains(dayNumber)) {
      done.remove(dayNumber);
    } else {
      done.add(dayNumber);
    }
    habit.completedDays = done;
    await habit.save();
  }

  /// Logs or removes a slip on [dayNumber] for a bad habit.
  Future<void> toggleSlip(Habit habit, int dayNumber) async {
    final slips = habit.slipDays.toList();
    if (slips.contains(dayNumber)) {
      slips.remove(dayNumber);
    } else {
      slips.add(dayNumber);
    }
    habit.slipDays = slips..sort();
    await habit.save();
  }

  String exportToJson() {
    final habits = getAll();
    final list = habits.map((h) => h.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  Future<void> importFromJson(String jsonString) async {
    final List<dynamic> list = jsonDecode(jsonString) as List<dynamic>;
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final habit = Habit.fromJson(item);
        await add(habit);
      }
    }
  }

  Stream<BoxEvent> watch() => _box.watch();
}

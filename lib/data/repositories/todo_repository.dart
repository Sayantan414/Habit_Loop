import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/todo.dart';

class TodoRepository {
  TodoRepository(this._box);

  static const boxName = 'todos';

  final Box<Todo> _box;

  List<Todo> getAll() => _box.values.toList(growable: false);

  Future<void> add(Todo todo) => _box.put(todo.id, todo);

  Future<void> toggle(Todo todo) async {
    todo.isCompleted = !todo.isCompleted;
    await todo.save();
  }

  Future<void> delete(String id) => _box.delete(id);

  Future<void> clearCompleted() async {
    final completed = _box.values.where((t) => t.isCompleted).toList();
    for (final t in completed) {
      await _box.delete(t.id);
    }
  }

  List<Map<String, dynamic>> exportToJsonList() {
    return getAll().map((t) => t.toJson()).toList();
  }

  Future<void> importFromJsonList(List<dynamic> list) async {
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final todo = Todo.fromJson(item);
        await add(todo);
      }
    }
  }

  Stream<BoxEvent> watch() => _box.watch();
}

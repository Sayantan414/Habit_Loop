import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/note.dart';

class NoteRepository {
  NoteRepository(this._box);

  static const boxName = 'notes';

  final Box<Note> _box;

  List<Note> getAll() => _box.values.toList(growable: false);

  Future<void> add(Note note) => _box.put(note.id, note);

  Future<void> update(Note note) => _box.put(note.id, note);

  Future<void> delete(String id) => _box.delete(id);

  List<Map<String, dynamic>> exportToJsonList() {
    return getAll().map((n) => n.toJson()).toList();
  }

  Future<void> importFromJsonList(List<dynamic> list) async {
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final note = Note.fromJson(item);
        await add(note);
      }
    }
  }

  Stream<BoxEvent> watch() => _box.watch();
}

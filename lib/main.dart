import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/services/settings_service.dart';
import 'data/models/habit.dart';
import 'data/repositories/habit_repository.dart';
import 'data/models/todo.dart';
import 'data/repositories/todo_repository.dart';
import 'data/models/note.dart';
import 'data/repositories/note_repository.dart';
import 'hive_registrar.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapters();
  final habitBox = await Hive.openBox<Habit>(HabitRepository.boxName);
  final habitRepository = HabitRepository(habitBox);

  final todoBox = await Hive.openBox<Todo>(TodoRepository.boxName);
  final todoRepository = TodoRepository(todoBox);

  final noteBox = await Hive.openBox<Note>(NoteRepository.boxName);
  final noteRepository = NoteRepository(noteBox);

  final settingsService = await SettingsService.create();

  runApp(
    ProviderScope(
      overrides: [
        habitRepositoryProvider.overrideWithValue(habitRepository),
        todoRepositoryProvider.overrideWithValue(todoRepository),
        noteRepositoryProvider.overrideWithValue(noteRepository),
        settingsServiceProvider.overrideWithValue(settingsService),
      ],
      child: const HabitLoopApp(),
    ),
  );
}

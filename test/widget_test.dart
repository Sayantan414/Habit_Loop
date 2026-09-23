// Basic smoke test: the app boots with an empty habit list and shows the
// "no habits yet" empty state.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:habit_loop/app.dart';
import 'package:habit_loop/core/providers.dart';
import 'package:habit_loop/core/services/settings_service.dart';
import 'package:habit_loop/data/models/habit.dart';
import 'package:habit_loop/data/models/todo.dart';
import 'package:habit_loop/data/models/note.dart';
import 'package:habit_loop/data/repositories/habit_repository.dart';
import 'package:habit_loop/data/repositories/todo_repository.dart';
import 'package:habit_loop/data/repositories/note_repository.dart';
import 'package:habit_loop/hive_registrar.g.dart';

void main() {
  testWidgets('shows empty state with no habits', (WidgetTester tester) async {
    await tester.runAsync(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});

      final tempDir = await Directory.systemTemp.createTemp('habit_loop_test');
      Hive.init(tempDir.path);
      Hive.registerAdapters();
      final habitBox = await Hive.openBox<Habit>('${HabitRepository.boxName}_test');
      final habitRepository = HabitRepository(habitBox);

      final todoBox = await Hive.openBox<Todo>('${TodoRepository.boxName}_test');
      final todoRepository = TodoRepository(todoBox);

      final noteBox = await Hive.openBox<Note>('${NoteRepository.boxName}_test');
      final noteRepository = NoteRepository(noteBox);

      final settings = await SettingsService.create();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            habitRepositoryProvider.overrideWithValue(habitRepository),
            todoRepositoryProvider.overrideWithValue(todoRepository),
            noteRepositoryProvider.overrideWithValue(noteRepository),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const HabitLoopApp(),
        ),
      );

      await tester.pump();

      expect(find.text('No habits yet'), findsOneWidget);

      await habitBox.close();
      await todoBox.close();
      await noteBox.close();
      await tempDir.delete(recursive: true);
    });
  });
}

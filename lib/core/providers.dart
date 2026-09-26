import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/habit.dart';
import '../data/repositories/habit_repository.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/sound_service.dart';
import 'services/widget_service.dart';

import 'services/backup_service.dart';

import '../data/models/todo.dart';
import '../data/repositories/todo_repository.dart';
import '../data/models/note.dart';
import '../data/repositories/note_repository.dart';

/// Overridden in main() once Hive/SharedPreferences finish initializing.
final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  throw UnimplementedError('habitRepositoryProvider must be overridden in main()');
});

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  throw UnimplementedError('todoRepositoryProvider must be overridden in main()');
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  throw UnimplementedError('noteRepositoryProvider must be overridden in main()');
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService();
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError('settingsServiceProvider must be overridden in main()');
});

final soundServiceProvider = Provider<SoundService>((ref) {
  final settings = ref.watch(settingsServiceProvider);
  return SoundService(enabled: settings.getSoundEnabled());
});

/// A request for [AppShell] to switch tabs, e.g. from a home screen widget tap.
///
/// Each request is a fresh object (no value equality), so asking for the same
/// tab twice still notifies listeners.
class ShellTabRequest {
  ShellTabRequest(this.index);
  final int index;
}

final shellTabRequestProvider = StateProvider<ShellTabRequest?>((ref) => null);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._settings) : super(_settings.getThemeMode());
  final SettingsService _settings;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _settings.setThemeMode(mode);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(settingsServiceProvider));
});

class SoundEnabledNotifier extends StateNotifier<bool> {
  SoundEnabledNotifier(this._settings, this._sound) : super(_settings.getSoundEnabled());
  final SettingsService _settings;
  final SoundService _sound;

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    _sound.setEnabled(enabled);
    await _settings.setSoundEnabled(enabled);
  }
}

final soundEnabledProvider = StateNotifierProvider<SoundEnabledNotifier, bool>((ref) {
  return SoundEnabledNotifier(ref.watch(settingsServiceProvider), ref.watch(soundServiceProvider));
});

class HabitsNotifier extends StateNotifier<List<Habit>> {
  HabitsNotifier(this._repo, this._todoRepo, this._noteRepo, this._ref) : super(_repo.getAll()) {
    WidgetService.updateHabits(state);
    NotificationService.instance.syncAll(state);
  }

  final HabitRepository _repo;
  final TodoRepository _todoRepo;
  final NoteRepository _noteRepo;
  final Ref _ref;

  void _refresh() {
    state = _repo.getAll();
    WidgetService.updateHabits(state);
    NotificationService.instance.syncAll(state);
  }

  /// Re-plans reminders and republishes the home screen widget, e.g. when the
  /// app returns to the foreground on a new day.
  void refreshReminders() {
    NotificationService.instance.syncAll(state);
    WidgetService.updateHabits(state);
  }

  Future<void> addHabit({
    required String title,
    required int totalDays,
    required DateTime startDate,
    required int colorValue,
    bool isFixed = false,
    List<int> reminderTimes = const [],
  }) async {
    final habit = Habit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      totalDays: totalDays,
      startDate: startDate,
      colorValue: colorValue,
      isFixed: isFixed,
      reminderTimes: reminderTimes.toList()..sort(),
    );
    await _repo.add(habit);
    _refresh();
  }

  Future<void> toggleDay(Habit habit, int dayNumber) async {
    if (dayNumber != habit.todayDayNumber) return;
    await _repo.toggleDay(habit, dayNumber);
    _refresh();
  }

  Future<void> toggleToday(Habit habit) async {
    await toggleDay(habit, habit.todayDayNumber);
  }

  /// Handles the "Mark as done" button on a reminder. Never un-checks.
  Future<bool> markDoneFromReminder(String habitId) async {
    final habit = _repo.getById(habitId);
    if (habit == null || habit.archived || !habit.isActiveToday) return false;
    if (habit.isCompletedToday) return false;
    await toggleToday(habit);
    return true;
  }

  Future<void> setReminderTimes(Habit habit, List<int> minutes) async {
    await NotificationService.instance.clearToday(habit);
    habit.reminderTimes = minutes.toSet().toList()..sort();
    await updateHabit(habit);
  }

  Future<void> updateHabit(Habit habit) async {
    await _repo.update(habit);
    _refresh();
  }

  Future<void> deleteHabit(String id) async {
    final habit = _repo.getById(id);
    if (habit != null) await NotificationService.instance.clearToday(habit);
    await _repo.delete(id);
    _refresh();
  }

  Future<void> setArchived(Habit habit, bool archived) async {
    habit.archived = archived;
    await _repo.update(habit);
    _refresh();
  }

  Future<void> togglePause(Habit habit) async {
    if (habit.isPaused) {
      if (habit.pausedAt != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final startPause = DateTime(
          habit.pausedAt!.year,
          habit.pausedAt!.month,
          habit.pausedAt!.day,
        );
        final pauseDays = today.difference(startPause).inDays;
        if (pauseDays > 0) {
          habit.startDate = habit.startDate.add(Duration(days: pauseDays));
        }
      }
      habit.isPaused = false;
      habit.pausedAt = null;
    } else {
      await NotificationService.instance.clearToday(habit);
      habit.isPaused = true;
      habit.pausedAt = DateTime.now();
    }
    await updateHabit(habit);
  }

  String exportJson() {
    final habitList = _repo.exportToJson();
    final habitJson = jsonDecode(habitList) as List<dynamic>;
    final todoJson = _todoRepo.exportToJsonList();
    final noteJson = _noteRepo.exportToJsonList();
    return const JsonEncoder.withIndent('  ').convert({
      'habits': habitJson,
      'todos': todoJson,
      'notes': noteJson,
    });
  }

  Future<void> importJson(String jsonString) async {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is Map<String, dynamic>) {
      if (decoded['habits'] is List) {
        await _repo.importFromJson(jsonEncode(decoded['habits']));
      }
      if (decoded['todos'] is List) {
        await _ref.read(todosProvider.notifier).importFromJsonList(decoded['todos'] as List<dynamic>);
      }
      if (decoded['notes'] is List) {
        await _ref.read(notesProvider.notifier).importFromJsonList(decoded['notes'] as List<dynamic>);
      }
    } else if (decoded is List) {
      await _repo.importFromJson(jsonString);
    }
    _refresh();
  }

  Future<String?> exportBackupToFile(BackupService service) async {
    final jsonStr = exportJson();
    return await service.saveJsonToDownloads(jsonStr);
  }

  Future<bool> importBackupFromFile(BackupService service) async {
    final jsonContent = await service.pickAndReadJsonFile();
    if (jsonContent != null && jsonContent.trim().isNotEmpty) {
      await importJson(jsonContent);
      return true;
    }
    return false;
  }
}

final habitsProvider = StateNotifierProvider<HabitsNotifier, List<Habit>>((ref) {
  return HabitsNotifier(
    ref.watch(habitRepositoryProvider),
    ref.watch(todoRepositoryProvider),
    ref.watch(noteRepositoryProvider),
    ref,
  );
});

class TodosNotifier extends StateNotifier<List<Todo>> {
  TodosNotifier(this._repo) : super(_repo.getAll()) {
    WidgetService.updateTodos(state);
  }
  final TodoRepository _repo;

  void _refresh() {
    state = _repo.getAll();
    WidgetService.updateTodos(state);
  }

  Future<void> addTodo(String title) async {
    final todo = Todo(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
    );
    await _repo.add(todo);
    _refresh();
  }

  Future<void> toggle(Todo todo) async {
    await _repo.toggle(todo);
    _refresh();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    _refresh();
  }

  Future<void> restoreTodo(Todo todo) async {
    await _repo.add(todo);
    _refresh();
  }

  Future<void> clearCompleted() async {
    await _repo.clearCompleted();
    _refresh();
  }

  List<Map<String, dynamic>> exportToJsonList() => _repo.exportToJsonList();

  Future<void> importFromJsonList(List<dynamic> list) async {
    await _repo.importFromJsonList(list);
    _refresh();
  }
}

final todosProvider = StateNotifierProvider<TodosNotifier, List<Todo>>((ref) {
  return TodosNotifier(ref.watch(todoRepositoryProvider));
});

final activeTodosProvider = Provider<List<Todo>>((ref) {
  final todos = ref.watch(todosProvider);
  return todos.where((t) => !t.isCompleted).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
});

final completedTodosProvider = Provider<List<Todo>>((ref) {
  final todos = ref.watch(todosProvider);
  return todos.where((t) => t.isCompleted).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Active (not archived, ongoing/un-finished, still within their day range) habits.
final activeHabitsProvider = Provider<List<Habit>>((ref) {
  final habits = ref.watch(habitsProvider);
  return habits.where((h) => !h.archived && h.isActiveToday && !h.isFinished).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
});

/// Habits that have run out their full day count.
final finishedHabitsProvider = Provider<List<Habit>>((ref) {
  final habits = ref.watch(habitsProvider);
  return habits.where((h) => !h.archived && h.isFinished).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Habits currently on pause.
final pausedHabitsProvider = Provider<List<Habit>>((ref) {
  final habits = ref.watch(habitsProvider);
  return habits.where((h) => !h.archived && h.isPaused).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
});

class TodaySummary {
  const TodaySummary(this.done, this.total);
  final int done;
  final int total;
  bool get allDone => total > 0 && done == total;
}

final todaySummaryProvider = Provider<TodaySummary>((ref) {
  final active = ref.watch(activeHabitsProvider);
  final done = active.where((h) => h.isCompletedToday).length;
  return TodaySummary(done, active.length);
});

class NotesNotifier extends StateNotifier<List<Note>> {
  NotesNotifier(this._repo) : super(_repo.getAll());
  final NoteRepository _repo;

  void _refresh() {
    state = _repo.getAll();
  }

  Future<Note> addNote({required String title, required String content}) async {
    final note = Note(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _repo.add(note);
    _refresh();
    return note;
  }

  Future<void> updateNote(Note note, {required String title, required String content}) async {
    note.title = title;
    note.content = content;
    note.updatedAt = DateTime.now();
    await _repo.update(note);
    _refresh();
  }

  Future<void> deleteNote(String id) async {
    await _repo.delete(id);
    _refresh();
  }

  List<Map<String, dynamic>> exportToJsonList() => _repo.exportToJsonList();

  Future<void> importFromJsonList(List<dynamic> list) async {
    await _repo.importFromJsonList(list);
    _refresh();
  }
}

final notesProvider = StateNotifierProvider<NotesNotifier, List<Note>>((ref) {
  return NotesNotifier(ref.watch(noteRepositoryProvider));
});

final searchQueryNotesProvider = StateProvider<String>((ref) => '');

final filteredNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider);
  final query = ref.watch(searchQueryNotesProvider).trim().toLowerCase();

  final sortedNotes = List<Note>.from(notes)
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  if (query.isEmpty) return sortedNotes;

  return sortedNotes.where((note) {
    return note.title.toLowerCase().contains(query) ||
        note.content.toLowerCase().contains(query);
  }).toList();
});

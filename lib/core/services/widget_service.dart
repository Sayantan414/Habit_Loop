import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../data/models/habit.dart';
import '../../data/models/todo.dart';
import '../theme/app_colors.dart';

/// Pushes today's habits and pending to-dos to the Android home screen widget.
///
/// Habits and to-dos are stored under separate keys so each notifier can
/// publish on its own schedule without clobbering the other's snapshot.
///
/// No-ops on platforms without a home screen widget (e.g. Windows), so it's
/// always safe to call from shared app code.
class WidgetService {
  static const _androidProviderName = 'HabitTodayWidgetProvider';

  static const _habitsKey = 'habits_snapshot';
  static const _todosKey = 'todos_snapshot';
  static const _enabledKey = 'widget_enabled';

  /// Deep links fired by taps on the widget (see [WidgetLink.parse]).
  static const scheme = 'habitloop';

  /// Shows or hides the widget's content. Apps can't remove a placed
  /// widget, so "hidden" draws a neutral card without any habit or to-do
  /// titles. Snapshots keep updating either way, so turning it back on is
  /// instantly current.
  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.saveWidgetData<bool>(_enabledKey, enabled);
      await HomeWidget.updateWidget(androidName: _androidProviderName);
    } catch (e) {
      // Ignore widget update platform exception if home widget class is not installed on device
    }
  }

  /// Whether the launcher can place the widget for the user (Android 8+,
  /// and only on launchers that support pinning).
  static Future<bool> canRequestPin() async {
    if (!Platform.isAndroid) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Asks the launcher to add the widget to the home screen.
  static Future<void> requestPin() async {
    if (!Platform.isAndroid) return;
    await HomeWidget.requestPinWidget(
      qualifiedAndroidName:
          'com.sayantan.habitloop.habit_loop.$_androidProviderName',
    );
  }

  static Future<void> updateHabits(List<Habit> habits) async {
    if (!Platform.isAndroid) return;

    // Same filter and ordering as activeHabitsProvider, so the widget's
    // counts always agree with the Today tab.
    final active = habits
        .where((h) => !h.isBad && !h.archived && h.isActiveToday && !h.isFinished)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final done = active.where((h) => h.isCompletedToday).length;
    final bestStreak = active.fold<int>(
      0,
      (best, h) => h.currentStreak > best ? h.currentStreak : best,
    );

    // Pending first: in a short widget the rows that still need a tap win.
    final ordered = [
      ...active.where((h) => !h.isCompletedToday),
      ...active.where((h) => h.isCompletedToday),
    ];

    final snapshot = {
      'day': _dayKey(DateTime.now()),
      'done': done,
      'total': active.length,
      'streak': bestStreak,
      'habits': [
        for (final h in ordered)
          {
            'id': h.id,
            'title': h.title,
            'done': h.isCompletedToday,
            'colorDark': AppAccents.resolve(h.colorValue, Brightness.dark).toARGB32(),
            'colorLight': AppAccents.resolve(h.colorValue, Brightness.light).toARGB32(),
          },
      ],
    };
    await _save(_habitsKey, snapshot);
  }

  static Future<void> updateTodos(List<Todo> todos) async {
    if (!Platform.isAndroid) return;

    final pending = todos.where((t) => !t.isCompleted).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final snapshot = {
      'count': pending.length,
      'todos': [
        // The widget shows at most a handful of rows.
        for (final t in pending.take(5)) {'id': t.id, 'title': t.title},
      ],
    };
    await _save(_todosKey, snapshot);
  }

  static Future<void> _save(String key, Map<String, Object?> snapshot) async {
    try {
      await HomeWidget.saveWidgetData<String>(key, jsonEncode(snapshot));
      await HomeWidget.updateWidget(androidName: _androidProviderName);
    } catch (e) {
      // Ignore widget update platform exception if home widget class is not installed on device
    }
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Where a widget tap asks the app to go.
sealed class WidgetLink {
  const WidgetLink();

  /// Parses `habitloop://today`, `habitloop://todo` and
  /// `habitloop://habit?id=<id>`. Unknown links fall back to Today.
  static WidgetLink? parse(Uri? uri) {
    if (uri == null || uri.scheme != WidgetService.scheme) return null;
    switch (uri.host) {
      case 'habit':
        final id = uri.queryParameters['id'];
        return id == null ? const TodayLink() : HabitLink(id);
      case 'todo':
        return const TodoLink();
      default:
        return const TodayLink();
    }
  }
}

class TodayLink extends WidgetLink {
  const TodayLink();
}

class TodoLink extends WidgetLink {
  const TodoLink();
}

class HabitLink extends WidgetLink {
  const HabitLink(this.habitId);
  final String habitId;
}

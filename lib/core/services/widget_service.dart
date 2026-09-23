import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../../data/models/habit.dart';

/// Pushes today's progress to the Android home screen widget.
///
/// No-ops on platforms without a home screen widget (e.g. Windows), so it's
/// always safe to call from shared app code.
class WidgetService {
  static const _androidProviderName = 'HabitTodayWidgetProvider';

  static Future<void> updateToday(List<Habit> habits) async {
    if (!Platform.isAndroid) return;

    try {
      final active = habits.where((h) => !h.archived && h.isActiveToday).toList();
      final doneCount = active.where((h) => h.isCompletedToday).length;
      final total = active.length;

      await HomeWidget.saveWidgetData<String>('habit_titles', active.map((h) => h.title).join('||'));
      await HomeWidget.saveWidgetData<String>(
        'habit_done_flags',
        active.map((h) => h.isCompletedToday ? '1' : '0').join('||'),
      );
      await HomeWidget.saveWidgetData<int>('done_count', doneCount);
      await HomeWidget.saveWidgetData<int>('total_count', total);
      await HomeWidget.saveWidgetData<bool>('all_done', total > 0 && doneCount == total);

      await HomeWidget.updateWidget(androidName: _androidProviderName);
    } catch (e) {
      // Ignore widget update platform exception if home widget class is not installed on device
    }
  }
}

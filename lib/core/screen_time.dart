import 'package:intl/intl.dart';

import '../data/models/habit.dart';

/// How many days of usage are read back from Android. Usage events are only
/// kept by the system for about a week, so older days are never re-checked.
const screenTimeHistoryDays = 7;

/// Key of [day] in [UsageService.dailyUsage] results.
String usageDayKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

/// Minutes spent on [habit]'s apps on [day], from a
/// [UsageService.dailyUsage] result.
int screenTimeOn(
  Habit habit,
  Map<String, Map<String, int>> usage,
  DateTime day,
) {
  final perApp = usage[usageDayKey(day)] ?? const <String, int>{};
  return habit.screenTimeApps.fold(0, (sum, pkg) => sum + (perApp[pkg] ?? 0));
}

/// The slip days [habit] should have given [usage]: a day over the limit is
/// a slip, a day at or under it is not.
///
/// Only days present in [usage] are judged. A day missing from it either had
/// no use at all (never a slip to begin with) or has been dropped from
/// Android's history — in which case the slip recorded back when the data
/// was there is kept.
Set<int> screenTimeSlips(
  Habit habit,
  Map<String, Map<String, int>> usage, {
  DateTime? now,
}) {
  final limit = habit.screenTimeLimit!;
  final today = habit.dayNumberFor(now ?? DateTime.now());
  final slips = habit.slipDays.toSet();
  for (var day = 1; day <= today; day++) {
    final date = habit.dateOfDay(day);
    if (!usage.containsKey(usageDayKey(date))) continue;
    screenTimeOn(habit, usage, date) > limit
        ? slips.add(day)
        : slips.remove(day);
  }
  return slips;
}

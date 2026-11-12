import '../../core/screen_time.dart';
import '../../data/models/habit.dart';
import '../../data/models/todo.dart';

enum ReportTopic { habits, todos, screenTime }

/// One habit over the report's days.
class HabitPeriod {
  const HabitPeriod({
    required this.title,
    required this.isBad,
    required this.done,
    required this.days,
    required this.slips,
    required this.streak,
  });

  final String title;
  final bool isBad;

  /// Check-ins (good habit) or clean finished days (bad habit).
  final int done;

  /// Days of the challenge that fell in the period, up to today.
  final int days;
  final int slips;
  final int streak;
}

/// Where the to-do list stands. To-dos keep no completion date, so these
/// are counts as of today plus what was added during the period.
class TodoSummary {
  const TodoSummary({
    required this.open,
    required this.done,
    required this.addedInPeriod,
    this.oldestOpen,
    this.oldestOpenDays = 0,
  });

  final int open;
  final int done;
  final int addedInPeriod;
  final String? oldestOpen;
  final int oldestOpenDays;
}

/// Minutes on the apps screen-time habits track, over the period, from
/// Android's usage history.
class ScreenTimeSummary {
  const ScreenTimeSummary({
    required this.byDay,
    required this.byApp,
    this.labels = const {},
    this.trackedApps = 0,
    this.previousTotal,
  });

  /// Minutes per day, oldest first.
  final List<int> byDay;

  /// Package name → minutes in the period, most first.
  final Map<String, int> byApp;

  /// Package name → app name, for display.
  final Map<String, String> labels;

  /// How many apps running screen-time habits track; 0 means there is
  /// nothing to report on.
  final int trackedApps;

  /// The same number of days just before, when Android's history goes back
  /// that far; null otherwise.
  final int? previousTotal;

  int get total => byDay.fold(0, (sum, c) => sum + c);

  double get perDay => byDay.isEmpty ? 0 : total / byDay.length;

  /// Index into [byDay] of the day with the most minutes.
  int get busiestDay {
    var best = 0;
    for (var i = 1; i < byDay.length; i++) {
      if (byDay[i] > byDay[best]) best = i;
    }
    return best;
  }
}

/// A report over the last [days] days (today included), for whichever
/// topics were asked for, worked out on the phone from what's already
/// stored. Nothing here needs the network.
class AssistantReport {
  const AssistantReport({
    required this.days,
    required this.from,
    required this.to,
    this.habits,
    this.todos,
    this.screenTime,
  });

  static const maxDays = 365;

  final int days;
  final DateTime from;
  final DateTime to;

  /// Null when the topic wasn't asked for.
  final List<HabitPeriod>? habits;
  final TodoSummary? todos;
  final ScreenTimeSummary? screenTime;

  /// How many days of usage [compute] needs for [days], including the
  /// period before it for comparison.
  static int screenTimeDaysNeeded(int days) =>
      (days * 2).clamp(1, screenTimeHistoryDays);

  static AssistantReport compute({
    required int days,
    required Set<ReportTopic> topics,
    List<Habit> habits = const [],
    List<Todo> todos = const [],
    Map<String, Map<String, int>> screenTimeUsage = const {},
    Map<String, String> appLabels = const {},
    bool hasScreenTime = false,
    DateTime? now,
  }) {
    final span = days.clamp(1, maxDays);
    final today = _day(now ?? DateTime.now());
    final from = DateTime(today.year, today.month, today.day - (span - 1));
    DateTime dayAt(int i) => DateTime(from.year, from.month, from.day + i);

    List<HabitPeriod>? habitPart;
    if (topics.contains(ReportTopic.habits)) {
      habitPart = [];
      for (final habit in habits) {
        if (habit.archived) continue;
        var inRange = 0;
        var done = 0;
        var slips = 0;
        for (var i = 0; i < span; i++) {
          final date = dayAt(i);
          final n = habit.dayNumberFor(date);
          if (n < 1 || n > habit.effectiveTotalDays) continue;
          inRange++;
          if (habit.isBad) {
            if (habit.slipDays.contains(n)) {
              slips++;
            } else if (date.isBefore(today)) {
              done++;
            }
          } else if (habit.completedDays.contains(n)) {
            done++;
          }
        }
        if (inRange == 0) continue;
        habitPart.add(
          HabitPeriod(
            title: habit.title,
            isBad: habit.isBad,
            done: done,
            days: inRange,
            slips: slips,
            streak: habit.currentStreak,
          ),
        );
      }
    }

    TodoSummary? todoPart;
    if (topics.contains(ReportTopic.todos)) {
      final open = todos.where((t) => !t.isCompleted).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final oldest = open.isEmpty ? null : open.first;
      todoPart = TodoSummary(
        open: open.length,
        done: todos.length - open.length,
        addedInPeriod: todos
            .where((t) => !_day(t.createdAt).isBefore(from))
            .length,
        oldestOpen: oldest?.title,
        oldestOpenDays: oldest == null
            ? 0
            : today.difference(_day(oldest.createdAt)).inDays,
      );
    }

    ScreenTimeSummary? screenPart;
    if (topics.contains(ReportTopic.screenTime) && hasScreenTime) {
      final tracked = {
        for (final h in habits)
          if (h.isScreenTimeHabit && !h.archived) ...h.screenTimeApps,
      };
      int totalOn(DateTime day) =>
          (screenTimeUsage[usageDayKey(day)] ?? const {}).entries
              .where((e) => tracked.contains(e.key))
              .fold(0, (sum, e) => sum + e.value);
      // Android keeps about a week of usage, so a longer report covers
      // what it has.
      final usageSpan = span.clamp(1, screenTimeHistoryDays);
      final usageFrom = span - usageSpan;
      final byApp = <String, int>{};
      for (var i = usageFrom; i < span; i++) {
        (screenTimeUsage[usageDayKey(dayAt(i))] ?? const {}).forEach((
          app,
          minutes,
        ) {
          if (tracked.contains(app)) byApp[app] = (byApp[app] ?? 0) + minutes;
        });
      }
      final hasPrevious = span * 2 <= screenTimeHistoryDays;
      screenPart = ScreenTimeSummary(
        labels: appLabels,
        trackedApps: tracked.length,
        byDay: [for (var i = usageFrom; i < span; i++) totalOn(dayAt(i))],
        byApp: Map.fromEntries(
          byApp.entries.where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value)),
        ),
        previousTotal: hasPrevious
            ? [
                for (var i = 1; i <= span; i++)
                  totalOn(DateTime(from.year, from.month, from.day - i)),
              ].fold<int>(0, (sum, c) => sum + c)
            : null,
      );
    }

    return AssistantReport(
      days: span,
      from: from,
      to: today,
      habits: habitPart,
      todos: todoPart,
      screenTime: screenPart,
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}

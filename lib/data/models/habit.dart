import 'package:hive_ce/hive.dart';

part 'habit.g.dart';

/// A single habit the user is trying to build, run over a fixed number
/// of days (e.g. "Exercise" for 21 days).
@HiveType(typeId: 0)
class Habit extends HiveObject {
  Habit({
    required this.id,
    required this.title,
    required this.totalDays,
    required this.startDate,
    required this.colorValue,
    DateTime? createdAt,
    List<int>? completedDays,
    this.archived = false,
    this.isFixed = false,
    List<int>? reminderTimes,
    this.isPaused = false,
    this.pausedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       completedDays = completedDays ?? <int>[],
       reminderTimes = reminderTimes ?? <int>[];

  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  /// How many days this habit challenge runs for (e.g. 21, 30, 60).
  @HiveField(2)
  int totalDays;

  /// The day the challenge started. Day 1 is this date.
  @HiveField(3)
  DateTime startDate;

  /// ARGB color value used for this habit's accent color.
  @HiveField(4)
  int colorValue;

  @HiveField(5)
  DateTime createdAt;

  /// Day numbers (1-based) that have been checked off.
  @HiveField(6)
  List<int> completedDays;

  /// True once the user has archived/dismissed this habit
  /// (kept for history, hidden from the active list).
  @HiveField(7)
  bool archived;

  /// True if the habit has a fixed duration (missed days do not extend the end date).
  /// False (Extended) if missed days add +1 extra day to complete the target.
  @HiveField(8)
  bool isFixed;

  /// Daily reminder times, stored as minutes after midnight (e.g. 07:30 = 450).
  /// Empty means no reminders for this habit.
  @HiveField(9)
  List<int> reminderTimes;

  /// True if the habit is currently paused (e.g. during vacation/break).
  @HiveField(10)
  bool isPaused;

  /// The date/time when this habit was paused.
  @HiveField(11)
  DateTime? pausedAt;

  /// 1-based day number for [date], relative to [startDate].
  int dayNumberFor(DateTime date) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final d = DateTime(date.year, date.month, date.day);
    return d.difference(start).inDays + 1;
  }

  int get todayDayNumber => dayNumberFor(DateTime.now());

  /// Number of past days (before today) that were missed (not completed).
  int get missedDaysCount {
    var count = 0;
    final maxPastDay = todayDayNumber - 1;
    for (var d = 1; d <= maxPastDay; d++) {
      if (!completedDays.contains(d)) {
        count++;
      }
    }
    return count;
  }

  /// Total target days including +1 extra day added at the end for each missed past day (if Extended mode).
  int get effectiveTotalDays =>
      isFixed ? totalDays : (totalDays + missedDaysCount);

  /// Whether today falls within the habit's active day range (and is not paused).
  bool get isActiveToday =>
      !isPaused && todayDayNumber >= 1 && todayDayNumber <= effectiveTotalDays;

  bool get isCompletedToday => completedDays.contains(todayDayNumber);

  bool isDayCompleted(int dayNumber) => completedDays.contains(dayNumber);

  /// True once the target number of days has been completed OR (for Fixed mode) when duration expires.
  bool get isFinished =>
      completedDays.length >= totalDays ||
      (isFixed && todayDayNumber > totalDays);

  /// Progress towards completing the target number of days (totalDays).
  double get progress =>
      totalDays == 0 ? 0 : (completedDays.length / totalDays).clamp(0.0, 1.0);

  /// Current consecutive streak counting back from today (or from the
  /// last active day if the challenge already ended).
  int get currentStreak {
    final done = completedDays.toSet();
    var streak = 0;
    var day = todayDayNumber > effectiveTotalDays
        ? effectiveTotalDays
        : todayDayNumber;
    while (day >= 1 && done.contains(day)) {
      streak++;
      day--;
    }
    return streak;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'totalDays': totalDays,
      'startDate': startDate.toIso8601String(),
      'colorValue': colorValue,
      'createdAt': createdAt.toIso8601String(),
      'completedDays': completedDays,
      'archived': archived,
      'isFixed': isFixed,
      'reminderTimes': reminderTimes,
      'isPaused': isPaused,
      'pausedAt': pausedAt?.toIso8601String(),
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as String,
      title: json['title'] as String,
      totalDays: json['totalDays'] as int,
      startDate: DateTime.parse(json['startDate'] as String),
      colorValue: json['colorValue'] as int,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      completedDays: (json['completedDays'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      archived: json['archived'] as bool? ?? false,
      isFixed: json['isFixed'] as bool? ?? false,
      reminderTimes: (json['reminderTimes'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      isPaused: json['isPaused'] as bool? ?? false,
      pausedAt: json['pausedAt'] != null
          ? DateTime.parse(json['pausedAt'] as String)
          : null,
    );
  }
}

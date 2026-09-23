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
  })  : createdAt = createdAt ?? DateTime.now(),
        completedDays = completedDays ?? <int>[];

  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  /// How many days this habit challenge runs for (e.g. 21, 30, 66).
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

  /// Total target days including +1 extra day added at the end for each missed past day.
  int get effectiveTotalDays => totalDays + missedDaysCount;

  /// Whether today falls within the habit's active day range.
  bool get isActiveToday => todayDayNumber >= 1 && todayDayNumber <= effectiveTotalDays;

  bool get isCompletedToday => completedDays.contains(todayDayNumber);

  bool isDayCompleted(int dayNumber) => completedDays.contains(dayNumber);

  /// True once every day in the challenge has been checked off.
  bool get isFinished => completedDays.length >= effectiveTotalDays;

  double get progress => effectiveTotalDays == 0 ? 0 : (completedDays.length / effectiveTotalDays).clamp(0.0, 1.0);

  /// Current consecutive streak counting back from today (or from the
  /// last active day if the challenge already ended).
  int get currentStreak {
    final done = completedDays.toSet();
    var streak = 0;
    var day = todayDayNumber > effectiveTotalDays ? effectiveTotalDays : todayDayNumber;
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
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as String,
      title: json['title'] as String,
      totalDays: json['totalDays'] as int,
      startDate: DateTime.parse(json['startDate'] as String),
      colorValue: json['colorValue'] as int,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
      completedDays: (json['completedDays'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList(),
      archived: json['archived'] as bool? ?? false,
    );
  }
}

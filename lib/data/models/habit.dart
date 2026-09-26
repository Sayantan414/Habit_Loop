import 'package:hive_ce/hive.dart';

part 'habit.g.dart';

/// A single habit the user is trying to build (e.g. "Exercise" for 21 days)
/// or quit (e.g. "No cigarettes" for 7 days), run over a fixed number of days.
///
/// Good habits are checked in once a day. Bad habits work the other way
/// round: every day that passes counts as clean unless a slip is logged.
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
    this.isBad = false,
    List<int>? slipDays,
    this.isStrict = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       completedDays = completedDays ?? <int>[],
       reminderTimes = reminderTimes ?? <int>[],
       slipDays = slipDays ?? <int>[];

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

  /// True for a habit the user is quitting rather than building.
  @HiveField(12, defaultValue: false)
  bool isBad;

  /// Day numbers (1-based) on which the user logged a slip. Bad habits only.
  @HiveField(13, defaultValue: [])
  List<int> slipDays;

  /// Bad habits only: a slip restarts the count, so the challenge is only
  /// finished after [totalDays] clean days in a row. Takes precedence over
  /// [isFixed].
  @HiveField(14, defaultValue: false)
  bool isStrict;

  /// 1-based day number for [date], relative to [startDate].
  int dayNumberFor(DateTime date) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final d = DateTime(date.year, date.month, date.day);
    return d.difference(start).inDays + 1;
  }

  int get todayDayNumber => dayNumberFor(DateTime.now());

  /// Number of past days (before today) that were missed (not completed).
  /// For a bad habit this is the number of slips logged so far.
  int get missedDaysCount {
    if (isBad) return _slipsUpTo(todayDayNumber);
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
  /// A Strict bad habit needs [totalDays] clean days after its last slip.
  int get effectiveTotalDays {
    if (isBad && isStrict) return _lastSlipDay + totalDays;
    return isFixed ? totalDays : (totalDays + missedDaysCount);
  }

  /// Whether today falls within the habit's active day range (and is not paused).
  bool get isActiveToday =>
      !isPaused && todayDayNumber >= 1 && todayDayNumber <= effectiveTotalDays;

  /// Always false for a bad habit — there is nothing to check in.
  bool get isCompletedToday =>
      !isBad && completedDays.contains(todayDayNumber);

  bool get isSlippedToday => isBad && slipDays.contains(todayDayNumber);

  /// Good habit: the day was checked in. Bad habit: the day is over and had
  /// no slip.
  bool isDayCompleted(int dayNumber) {
    if (!isBad) return completedDays.contains(dayNumber);
    return dayNumber >= 1 &&
        dayNumber < todayDayNumber &&
        !slipDays.contains(dayNumber);
  }

  /// Good habit: a past day that wasn't checked in. Bad habit: a slip day
  /// (including today).
  bool isDayMissed(int dayNumber) {
    if (isBad) return slipDays.contains(dayNumber);
    return dayNumber < todayDayNumber && !completedDays.contains(dayNumber);
  }

  /// Check-ins for a good habit, finished clean days for a bad one.
  int get doneDaysCount {
    if (!isBad) return completedDays.length;
    final lastPast = (todayDayNumber - 1).clamp(0, effectiveTotalDays);
    var count = 0;
    for (var d = 1; d <= lastPast; d++) {
      if (!slipDays.contains(d)) count++;
    }
    return count;
  }

  /// True once the target number of days has been completed OR (for Fixed mode) when duration expires.
  /// A bad habit is finished once its whole (possibly extended) run is over.
  bool get isFinished {
    if (isBad) return !isPaused && todayDayNumber > effectiveTotalDays;
    return completedDays.length >= totalDays ||
        (isFixed && todayDayNumber > totalDays);
  }

  /// Progress towards completing the target number of days (totalDays).
  double get progress {
    if (totalDays == 0) return 0;
    final done = isBad && isStrict ? currentStreak : doneDaysCount;
    return (done / totalDays).clamp(0.0, 1.0);
  }

  /// Current consecutive streak counting back from today (or from the
  /// last active day if the challenge already ended).
  ///
  /// For a bad habit: finished days clean since the last slip ("5 days
  /// clean"). A slip today drops it to 0.
  int get currentStreak {
    if (isBad) {
      if (isSlippedToday) return 0;
      var streak = 0;
      var day = (todayDayNumber - 1).clamp(0, effectiveTotalDays);
      while (day >= 1 && !slipDays.contains(day)) {
        streak++;
        day--;
      }
      return streak;
    }
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

  int get _lastSlipDay =>
      slipDays.fold(0, (last, d) => d > last && d <= todayDayNumber ? d : last);

  int _slipsUpTo(int dayNumber) =>
      slipDays.where((d) => d >= 1 && d <= dayNumber).length;

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
      'isBad': isBad,
      'slipDays': slipDays,
      'isStrict': isStrict,
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
      isBad: json['isBad'] as bool? ?? false,
      slipDays: (json['slipDays'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      isStrict: json['isStrict'] as bool? ?? false,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_loop/data/models/habit.dart';

/// A bad habit whose day 1 was [daysAgo] days ago, so today is day
/// `daysAgo + 1`.
Habit _quit({
  required int daysAgo,
  int totalDays = 7,
  List<int>? slips,
  bool isFixed = false,
  bool isStrict = false,
}) {
  return Habit(
    id: 'q',
    title: 'No cigarettes',
    totalDays: totalDays,
    startDate: DateTime.now().subtract(Duration(days: daysAgo)),
    colorValue: 0,
    isBad: true,
    slipDays: slips,
    isFixed: isFixed,
    isStrict: isStrict,
  );
}

void main() {
  group('Bad habit', () {
    test('past days count as clean by default; today does not yet', () {
      final h = _quit(daysAgo: 3); // today is day 4
      expect(h.doneDaysCount, 3);
      expect(h.currentStreak, 3);
      expect(h.isDayCompleted(3), isTrue);
      expect(h.isDayCompleted(4), isFalse);
      expect(h.isCompletedToday, isFalse);
      expect(h.isActiveToday, isTrue);
      expect(h.isFinished, isFalse);
    });

    test('finishes once all days have passed with no slips', () {
      final h = _quit(daysAgo: 7); // today is day 8 of 7
      expect(h.isFinished, isTrue);
      expect(h.doneDaysCount, 7);
      expect(h.progress, 1.0);
    });

    test('Extended: a slip adds a day and resets the streak only', () {
      final h = _quit(daysAgo: 5, slips: [3]); // today is day 6
      expect(h.missedDaysCount, 1);
      expect(h.effectiveTotalDays, 8);
      expect(h.doneDaysCount, 4);
      expect(h.currentStreak, 2); // days 4 and 5
      expect(h.isDayMissed(3), isTrue);
      expect(h.isDayCompleted(3), isFalse);

      final later = _quit(daysAgo: 7, slips: [3]); // day 8 of 8
      expect(later.isFinished, isFalse);
      final done = _quit(daysAgo: 8, slips: [3]); // day 9
      expect(done.isFinished, isTrue);
      expect(done.doneDaysCount, 7);
    });

    test('a slip today zeroes the streak and extends the run', () {
      final h = _quit(daysAgo: 2, slips: [3]); // slipped on today (day 3)
      expect(h.isSlippedToday, isTrue);
      expect(h.currentStreak, 0);
      expect(h.effectiveTotalDays, 8);
    });

    test('Fixed: slips do not move the end date', () {
      final h = _quit(daysAgo: 7, slips: [2, 5], isFixed: true);
      expect(h.effectiveTotalDays, 7);
      expect(h.isFinished, isTrue);
      expect(h.doneDaysCount, 5);
    });

    test('Strict: needs totalDays clean days after the last slip', () {
      final h = _quit(daysAgo: 5, slips: [4], isStrict: true); // day 6
      expect(h.effectiveTotalDays, 11);
      expect(h.currentStreak, 1);
      expect(h.progress, closeTo(1 / 7, 1e-9));
      expect(_quit(daysAgo: 10, slips: [4], isStrict: true).isFinished, isFalse);
      expect(_quit(daysAgo: 11, slips: [4], isStrict: true).isFinished, isTrue);
    });

    test('does not finish while paused', () {
      final h = _quit(daysAgo: 20)..isPaused = true;
      expect(h.isFinished, isFalse);
    });

    test('round-trips through JSON; old backups default to a good habit', () {
      final h = _quit(daysAgo: 1, slips: [1], isStrict: true);
      final copy = Habit.fromJson(h.toJson());
      expect(copy.isBad, isTrue);
      expect(copy.isStrict, isTrue);
      expect(copy.slipDays, [1]);

      final legacy = h.toJson()
        ..remove('isBad')
        ..remove('slipDays')
        ..remove('isStrict');
      final old = Habit.fromJson(legacy);
      expect(old.isBad, isFalse);
      expect(old.slipDays, isEmpty);
    });
  });
}

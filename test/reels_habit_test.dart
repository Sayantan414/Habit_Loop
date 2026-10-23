import 'package:flutter_test/flutter_test.dart';
import 'package:habit_loop/data/models/habit.dart';

Habit _habit({bool isBad = true, int? reelsTarget, DateTime? startDate}) {
  return Habit(
    id: 'r',
    title: 'Max 50 reels a day',
    totalDays: 30,
    startDate: startDate ?? DateTime(2026, 10, 1, 21, 30),
    colorValue: 0,
    isBad: isBad,
    reelsTarget: reelsTarget,
  );
}

void main() {
  group('Reels habit', () {
    test('is a quit habit with a reels target', () {
      expect(_habit(reelsTarget: 50).isReelsHabit, isTrue);
      expect(_habit().isReelsHabit, isFalse);
      // A target on a build habit is meaningless and ignored.
      expect(_habit(isBad: false, reelsTarget: 50).isReelsHabit, isFalse);
    });

    test('dateOfDay maps day numbers to calendar dates', () {
      final h = _habit(reelsTarget: 50);
      expect(h.dateOfDay(1), DateTime(2026, 10, 1));
      expect(h.dateOfDay(31), DateTime(2026, 10, 31));
      expect(h.dateOfDay(32), DateTime(2026, 11, 1));
      expect(h.dayNumberFor(h.dateOfDay(17)), 17);
    });

    test('round-trips through JSON; old backups have no target', () {
      final copy = Habit.fromJson(_habit(reelsTarget: 50).toJson());
      expect(copy.reelsTarget, 50);
      expect(copy.isReelsHabit, isTrue);

      final legacy = _habit(reelsTarget: 50).toJson()..remove('reelsTarget');
      expect(Habit.fromJson(legacy).isReelsHabit, isFalse);
    });
  });
}

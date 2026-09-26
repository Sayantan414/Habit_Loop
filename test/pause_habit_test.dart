import 'package:flutter_test/flutter_test.dart';
import 'package:habit_loop/data/models/habit.dart';

void main() {
  group('Habit Pause / Resume logic tests', () {
    test('Habit is not active today when paused', () {
      final habit = Habit(
        id: '1',
        title: 'Exercise',
        totalDays: 7,
        startDate: DateTime.now().subtract(const Duration(days: 2)),
        colorValue: 0xFF4CAF50,
      );

      expect(habit.isActiveToday, isTrue);
      expect(habit.isPaused, isFalse);

      // Pause habit
      habit.isPaused = true;
      habit.pausedAt = DateTime.now();

      expect(habit.isActiveToday, isFalse);
    });

    test('Resuming after pause shifts startDate by paused duration', () {
      final initialStart = DateTime(2026, 9, 20);
      final habit = Habit(
        id: '2',
        title: 'Reading',
        totalDays: 7,
        startDate: initialStart,
        colorValue: 0xFF2196F3,
        isPaused: true,
        pausedAt: DateTime(2026, 9, 22),
      );

      // Simulate resume 2 days later on 2026-09-24
      final now = DateTime(2026, 9, 24);
      final startPause = DateTime(
        habit.pausedAt!.year,
        habit.pausedAt!.month,
        habit.pausedAt!.day,
      );
      final pauseDays = DateTime(now.year, now.month, now.day)
          .difference(startPause)
          .inDays;

      expect(pauseDays, equals(2));

      if (pauseDays > 0) {
        habit.startDate = habit.startDate.add(Duration(days: pauseDays));
      }
      habit.isPaused = false;
      habit.pausedAt = null;

      expect(habit.isPaused, isFalse);
      expect(habit.startDate, equals(DateTime(2026, 9, 22)));
    });
  });
}

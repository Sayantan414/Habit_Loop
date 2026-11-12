import 'package:flutter_test/flutter_test.dart';
import 'package:habit_loop/core/screen_time.dart';
import 'package:habit_loop/data/models/habit.dart';

Habit _habit({
  bool isBad = true,
  int? screenTimeLimit,
  List<String>? screenTimeApps,
  List<int>? slipDays,
}) {
  return Habit(
    id: 's',
    title: 'Instagram under 45 min',
    totalDays: 30,
    startDate: DateTime(2026, 11, 1),
    colorValue: 0,
    isBad: isBad,
    screenTimeLimit: screenTimeLimit,
    screenTimeApps: screenTimeApps,
    slipDays: slipDays,
  );
}

void main() {
  group('Screen-time habit', () {
    const apps = ['com.instagram.android', 'com.google.android.youtube'];

    test('is a quit habit with a limit and at least one app', () {
      expect(
        _habit(screenTimeLimit: 45, screenTimeApps: apps).isScreenTimeHabit,
        isTrue,
      );
      expect(_habit().isScreenTimeHabit, isFalse);
      // A limit with no apps has nothing to measure.
      expect(_habit(screenTimeLimit: 45).isScreenTimeHabit, isFalse);
      // A limit on a build habit is meaningless and ignored.
      expect(
        _habit(isBad: false, screenTimeLimit: 45, screenTimeApps: apps)
            .isScreenTimeHabit,
        isFalse,
      );
    });

    test('round-trips through JSON; old backups have no limit', () {
      final copy = Habit.fromJson(
        _habit(screenTimeLimit: 45, screenTimeApps: apps).toJson(),
      );
      expect(copy.screenTimeLimit, 45);
      expect(copy.screenTimeApps, apps);
      expect(copy.isScreenTimeHabit, isTrue);

      final legacy = _habit(screenTimeLimit: 45, screenTimeApps: apps).toJson()
        ..remove('screenTimeLimit')
        ..remove('screenTimeApps');
      final old = Habit.fromJson(legacy);
      expect(old.screenTimeApps, isEmpty);
      expect(old.isScreenTimeHabit, isFalse);
    });
  
    group('auto slips', () {
      const insta = 'com.instagram.android';
      const yt = 'com.google.android.youtube';
      // Habit starts Nov 1; "now" is Nov 5 (day 5).
      final now = DateTime(2026, 11, 5, 20);

      test('a day over the limit across all apps is a slip', () {
        final h = _habit(screenTimeLimit: 45, screenTimeApps: apps);
        final slips = screenTimeSlips(h, {
          '2026-11-02': {insta: 30, yt: 20}, // 50 > 45
          '2026-11-03': {insta: 45}, // exactly the limit is fine
          '2026-11-05': {yt: 60}, // today counts live
        }, now: now);
        expect(slips, {2, 5});
      });

      test('apps outside the habit do not count', () {
        final h = _habit(screenTimeLimit: 30, screenTimeApps: const [insta]);
        final slips = screenTimeSlips(h, {
          '2026-11-02': {insta: 10, yt: 300},
        }, now: now);
        expect(slips, isEmpty);
      });

      test('a raised limit clears slips on days that are now under it', () {
        final h = _habit(
          screenTimeLimit: 60,
          screenTimeApps: apps,
          slipDays: [2],
        );
        final slips = screenTimeSlips(h, {
          '2026-11-02': {insta: 50},
        }, now: now);
        expect(slips, isEmpty);
      });

      test('days missing from the usage data keep their recorded slips', () {
        // Day 1 dropped out of Android's history after being logged.
        final h = _habit(
          screenTimeLimit: 45,
          screenTimeApps: apps,
          slipDays: [1],
        );
        final slips = screenTimeSlips(h, {
          '2026-11-04': {insta: 5},
        }, now: now);
        expect(slips, {1});
      });
    });
  });
}

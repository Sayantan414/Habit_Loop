import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_loop/core/theme/app_theme.dart';
import 'package:habit_loop/data/models/habit.dart';
import 'package:habit_loop/widgets/habit_card.dart';

Habit _habit({List<int>? slipDays}) {
  final now = DateTime.now();
  return Habit(
    id: 's',
    title: 'Instagram under 45 min',
    totalDays: 30,
    startDate: DateTime(now.year, now.month, now.day),
    colorValue: 0,
    isBad: true,
    screenTimeLimit: 45,
    screenTimeApps: const ['com.instagram.android'],
    slipDays: slipDays,
  );
}

Future<void> _pump(WidgetTester tester, Habit habit, int minutes) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AvoidHabitCard(
          habit: habit,
          screenMinutesToday: minutes,
          onTap: () {},
          onSlip: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows minutes used and left, with no slip button', (
    tester,
  ) async {
    await _pump(tester, _habit(), 32);
    expect(find.text('32 / 45 min'), findsOneWidget);
    expect(find.text('13 min left today'), findsOneWidget);
    expect(find.text('Slipped'), findsNothing);
  });

  testWidgets('says the day is over the limit once it slipped', (
    tester,
  ) async {
    await _pump(tester, _habit(slipDays: [1]), 50);
    expect(find.text('50 / 45 min'), findsOneWidget);
    expect(
      find.text('Over 45 min today — tomorrow is a fresh start.'),
      findsOneWidget,
    );
  });
}

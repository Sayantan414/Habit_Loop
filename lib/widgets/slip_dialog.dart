import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import '../data/models/habit.dart';

/// Logs or removes a slip on [dayNumber] of a bad habit.
///
/// Adding a slip asks first — a mis-tap would cost progress — and the copy
/// stays supportive, since "I've failed anyway" is what turns one slip into
/// many. Removing a slip is an undo and happens straight away.
Future<void> toggleSlipWithConfirm(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
  int dayNumber,
) async {
  final notifier = ref.read(habitsProvider.notifier);
  if (habit.slipDays.contains(dayNumber)) {
    await notifier.toggleSlip(habit, dayNumber);
    return;
  }

  final isToday = dayNumber == habit.todayDayNumber;
  final String consequence;
  if (habit.isStrict) {
    consequence =
        'Strict mode: your clean count restarts, and you\'ll need '
        '${habit.totalDays} clean days in a row from here.';
  } else if (habit.isFixed) {
    consequence =
        'It\'s recorded, and the challenge still ends on day ${habit.totalDays}.';
  } else {
    consequence =
        'One day is added to the end, so you still reach '
        '${habit.totalDays} clean days. Your progress is kept.';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final p = AppPalette.of(ctx);
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(isToday ? 'Log a slip for today?' : 'Log a slip on day $dayNumber?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(consequence, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppTokens.space3),
            Text(
              'A slip is not the end. What matters is the next clean day.',
              style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log slip'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  HapticFeedback.lightImpact();
  await notifier.toggleSlip(habit, dayNumber);
}

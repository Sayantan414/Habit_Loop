import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'pressable.dart';

/// Lets the user pick any number of daily reminder times for a habit.
///
/// Times are minutes after midnight (the same shape stored on `Habit`).
class ReminderTimesPicker extends StatelessWidget {
  const ReminderTimesPicker({
    super.key,
    required this.times,
    required this.color,
    required this.onChanged,
  });

  static const maxTimes = 6;

  final List<int> times;
  final Color color;
  final ValueChanged<List<int>> onChanged;

  Future<void> _add(BuildContext context) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (now.hour + 1) % 24, minute: 0),
      helpText: 'Remind me at',
    );
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    if (times.contains(minute)) return;
    onChanged([...times, minute]..sort());
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final sorted = times.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppTokens.space2,
          runSpacing: AppTokens.space2,
          children: [
            for (final minute in sorted)
              _TimeChip(
                label: TimeOfDay(
                  hour: minute ~/ 60,
                  minute: minute % 60,
                ).format(context),
                color: color,
                onRemove: () =>
                    onChanged(sorted.where((m) => m != minute).toList()),
              ),
            if (sorted.length < maxTimes)
              Pressable(
                onTap: () => _add(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: p.isDark
                        ? p.surfaceHigh.withValues(alpha: 0.5)
                        : p.surface,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(color: p.stroke),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_alarm_rounded, size: 17, color: color),
                      const SizedBox(width: 6),
                      Text(
                        'Add time',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.space2),
        Text(
          sorted.isEmpty
              ? 'No reminders. Add the times you want a nudge each day.'
              : 'Reminders stop for the day once you check this habit off.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            color: p.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.color,
    required this.onRemove,
  });

  final String label;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: color, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontFeatures: AppTypography.tabular,
            ),
          ),
          Pressable(
            onTap: onRemove,
            scale: 0.85,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 15, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

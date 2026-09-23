import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/models/habit.dart';

class HabitDetailScreen extends ConsumerWidget {
  const HabitDetailScreen({super.key, required this.habitId});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    Habit? habit;
    for (final h in habits) {
      if (h.id == habitId) {
        habit = h;
        break;
      }
    }

    if (habit == null) {
      return const Scaffold(body: Center(child: Text('Habit not found')));
    }
    final Habit currentHabit = habit;

    final theme = Theme.of(context);
    final color = Color(currentHabit.colorValue);
    final today = currentHabit.todayDayNumber;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentHabit.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete habit?'),
                    content: Text(
                      'This removes "${currentHabit.title}" and all its progress. This can\'t be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref
                      .read(habitsProvider.notifier)
                      .deleteHabit(currentHabit.id);
                  if (context.mounted) Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete habit')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              _StatChip(
                icon: Icons.check_circle_outline_rounded,
                label: 'Completed',
                value:
                    '${currentHabit.completedDays.length}/${currentHabit.effectiveTotalDays}',
                color: color,
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.local_fire_department_rounded,
                label: 'Streak',
                value: '${currentHabit.currentStreak}d',
                color: color,
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.pie_chart_outline_rounded,
                label: 'Progress',
                value: '${(currentHabit.progress * 100).round()}%',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: currentHabit.progress,
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Started ${DateFormat.yMMMd().format(currentHabit.startDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    currentHabit.missedDaysCount > 0
                        ? '${currentHabit.effectiveTotalDays} Days (+${currentHabit.missedDaysCount} missed)'
                        : '${currentHabit.totalDays} Days Target',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Challenge Days Calendar',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                'Only today is editable',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: currentHabit.effectiveTotalDays,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index + 1;
              final isDone = currentHabit.isDayCompleted(dayNumber);
              final isToday = dayNumber == today;
              final isMissed = dayNumber < today && !isDone;

              return _DayCell(
                dayNumber: dayNumber,
                isDone: isDone,
                isMissed: isMissed,
                isToday: isToday,
                color: color,
                onTap: isToday
                    ? () async {
                        await ref
                            .read(habitsProvider.notifier)
                            .toggleDay(currentHabit, dayNumber);
                        ref.read(soundServiceProvider).playCheck();
                      }
                    : () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Only today\'s habit task can be completed!',
                            ),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayNumber,
    required this.isDone,
    required this.isMissed,
    required this.isToday,
    required this.color,
    required this.onTap,
  });

  final int dayNumber;
  final bool isDone;
  final bool isMissed;
  final bool isToday;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: isDone
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color,
                    Color.lerp(color, Colors.black, 0.15) ?? color,
                  ],
                )
              : null,
          color: isDone
              ? null
              : isMissed
              ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isToday
                ? color
                : isDone
                ? color
                : isMissed
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.4)
                : color.withValues(alpha: 0.2),
            width: isToday ? 2.5 : 1,
          ),
          boxShadow: isDone
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: isDone
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
            : isMissed
            ? Icon(
                Icons.close_rounded,
                size: 16,
                color: muted.withValues(alpha: 0.5),
              )
            : Text(
                '$dayNumber',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isToday ? color : muted,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

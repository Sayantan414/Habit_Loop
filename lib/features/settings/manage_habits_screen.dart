import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/habit.dart';
import '../../widgets/app_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../add_habit/add_habit_screen.dart';
import '../habit_detail/habit_detail_screen.dart';

enum _HabitFilter { all, ongoing, paused, completed }

/// Edit or remove existing habits. Reached from Settings → Habits.
class ManageHabitsScreen extends ConsumerStatefulWidget {
  const ManageHabitsScreen({super.key});

  @override
  ConsumerState<ManageHabitsScreen> createState() => _ManageHabitsScreenState();
}

class _ManageHabitsScreenState extends ConsumerState<ManageHabitsScreen> {
  _HabitFilter _filter = _HabitFilter.all;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final habits = ref.watch(habitsProvider);

    final filteredHabits = habits.where((h) {
      switch (_filter) {
        case _HabitFilter.all:
          return true;
        case _HabitFilter.ongoing:
          return !h.isFinished && !h.isPaused;
        case _HabitFilter.paused:
          return h.isPaused;
        case _HabitFilter.completed:
          return h.isFinished;
      }
    }).toList();

    final ongoingCount = habits.where((h) => !h.isFinished && !h.isPaused).length;
    final pausedCount = habits.where((h) => h.isPaused).length;
    final completedCount = habits.where((h) => h.isFinished).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.isDark ? p.surfaceGlassHi : p.surface,
                          border: Border.all(color: p.stroke),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space3),
                    Expanded(
                      child: Text(
                        'Manage habits',
                        style: theme.textTheme.headlineSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<_HabitFilter>(
                      initialValue: _filter,
                      onSelected: (filter) => setState(() => _filter = filter),
                      color: p.isDark ? p.surfaceHigh : p.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        side: BorderSide(color: p.stroke),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: p.isDark ? p.surfaceGlassHi : p.surface,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusSm),
                          border: Border.all(color: p.stroke),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _filter == _HabitFilter.all
                                  ? 'All'
                                  : _filter == _HabitFilter.ongoing
                                      ? 'Ongoing'
                                      : _filter == _HabitFilter.paused
                                          ? 'Paused'
                                          : 'Completed',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: p.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _HabitFilter.all,
                          child: Text('All (${habits.length})'),
                        ),
                        PopupMenuItem(
                          value: _HabitFilter.ongoing,
                          child: Text('Ongoing ($ongoingCount)'),
                        ),
                        PopupMenuItem(
                          value: _HabitFilter.paused,
                          child: Text('Paused ($pausedCount)'),
                        ),
                        PopupMenuItem(
                          value: _HabitFilter.completed,
                          child: Text('Completed ($completedCount)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filteredHabits.isEmpty
                    ? _EmptyManage(filter: _filter)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.gutter,
                          AppTokens.space3,
                          AppTokens.gutter,
                          AppTokens.space8,
                        ),
                        itemCount: filteredHabits.length,
                        itemBuilder: (context, index) {
                          final habit = filteredHabits[index];
                          final color =
                              AppAccents.of(context, habit.colorValue);
                          final isCompleted = habit.isFinished;

                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTokens.space3,
                            ),
                            child: GlassCard(
                              accent: color,
                              padding: const EdgeInsets.all(AppTokens.space4),
                              onTap: isCompleted
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => HabitDetailScreen(
                                            habitId: habit.id,
                                          ),
                                        ),
                                      )
                                  : () => AddHabitScreen.push(
                                        context,
                                        habit: habit,
                                      ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                    ),
                                  ),
                                  const SizedBox(width: AppTokens.space3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                habit.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.titleMedium,
                                              ),
                                            ),
                                            if (isCompleted) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: p.success
                                                      .withValues(alpha: 0.16),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Completed',
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    fontSize: 10,
                                                    color: p.success,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          habit.isBad
                                              ? '${habit.totalDays}-day quit · '
                                                  '${habit.doneDaysCount} clean days'
                                              : '${habit.totalDays}-day challenge · '
                                                  '${habit.completedDays.length} checked in',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCompleted)
                                    Pressable(
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => HabitDetailScreen(
                                            habitId: habit.id,
                                          ),
                                        ),
                                      ),
                                      scale: 0.85,
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 20,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    )
                                  else
                                    Pressable(
                                      onTap: () => AddHabitScreen.push(
                                        context,
                                        habit: habit,
                                      ),
                                      scale: 0.85,
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.edit_rounded,
                                          size: 18,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ),
                                  Pressable(
                                    onTap: () => _confirmDelete(context, habit),
                                    scale: 0.85,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: p.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Habit habit) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit?'),
        content: Text(
          'All streak progress for "${habit.title}" will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.of(ctx).danger,
            ),
            onPressed: () async {
              await ref.read(habitsProvider.notifier).deleteHabit(habit.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyManage extends StatelessWidget {
  const _EmptyManage({this.filter = _HabitFilter.all});

  final _HabitFilter filter;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    final String message = filter == _HabitFilter.ongoing
        ? 'No ongoing habits found.'
        : filter == _HabitFilter.paused
            ? 'No paused habits found.'
            : filter == _HabitFilter.completed
                ? 'No completed habits found.'
                : 'Habits you create on the Today tab show up here.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: p.textTertiary),
            const SizedBox(height: AppTokens.space4),
            Text('No habits found', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppTokens.space2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

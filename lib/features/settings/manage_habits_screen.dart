import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/habit.dart';
import '../../widgets/app_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../add_habit/add_habit_screen.dart';

/// Edit or remove existing habits. Reached from Settings → Habits.
class ManageHabitsScreen extends ConsumerWidget {
  const ManageHabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final habits = ref.watch(habitsProvider);

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
                        child: Icon(Icons.arrow_back_rounded,
                            size: 20, color: p.textPrimary),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space3),
                    Text('Manage habits',
                        style: theme.textTheme.headlineSmall),
                  ],
                ),
              ),
              Expanded(
                child: habits.isEmpty
                    ? const _EmptyManage()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.gutter,
                          AppTokens.space3,
                          AppTokens.gutter,
                          AppTokens.space8,
                        ),
                        itemCount: habits.length,
                        itemBuilder: (context, index) {
                          final habit = habits[index];
                          final color =
                              AppAccents.of(context, habit.colorValue);

                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTokens.space3,
                            ),
                            child: GlassCard(
                              accent: color,
                              padding: const EdgeInsets.all(AppTokens.space4),
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
                                        Text(
                                          habit.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${habit.totalDays}-day challenge · '
                                          '${habit.completedDays.length} checked in',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Pressable(
                                    onTap: () => AddHabitScreen.push(
                                      context,
                                      habit: habit,
                                    ),
                                    scale: 0.85,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(Icons.edit_rounded,
                                          size: 18, color: p.textSecondary),
                                    ),
                                  ),
                                  Pressable(
                                    onTap: () =>
                                        _confirmDelete(context, ref, habit),
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

  void _confirmDelete(BuildContext context, WidgetRef ref, Habit habit) {
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
  const _EmptyManage();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: p.textTertiary),
            const SizedBox(height: AppTokens.space4),
            Text('No habits yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppTokens.space2),
            Text(
              'Habits you create on the Today tab show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

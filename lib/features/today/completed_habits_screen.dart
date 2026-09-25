import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/extend_habit_dialog.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../habit_detail/habit_detail_screen.dart';

/// Full screen page displaying completed habit challenges.
class CompletedHabitsScreen extends ConsumerWidget {
  const CompletedHabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finished = ref.watch(finishedHabitsProvider);
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
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
                    Text(
                      'Completed challenges',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.success.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                      ),
                      child: Text(
                        '${finished.length}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: p.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),

              // Content List
              Expanded(
                child: finished.isEmpty
                    ? Center(
                        child: Text(
                          'No completed challenges found.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.gutter,
                          AppTokens.space3,
                          AppTokens.gutter,
                          AppTokens.space8,
                        ),
                        itemCount: finished.length,
                        itemBuilder: (context, index) {
                          final habit = finished[index];
                          final color = AppAccents.of(context, habit.colorValue);

                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTokens.space3,
                            ),
                            child: GlassCard(
                              accent: color,
                              padding: const EdgeInsets.all(AppTokens.space4),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        HabitDetailScreen(habitId: habit.id),
                                  ),
                                );
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                        child: Text(
                                          habit.title,
                                          style: theme.textTheme.titleMedium,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: p.success.withValues(
                                            alpha: 0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppTokens.radiusSm,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle_rounded,
                                              size: 14,
                                              color: p.success,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Finished',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: p.success,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppTokens.space3),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${habit.totalDays}-day challenge completed',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      Pressable(
                                        onTap: () async {
                                          await showExtendHabitDialog(
                                            context,
                                            ref,
                                            habit,
                                          );
                                        },
                                        scale: 0.92,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              AppTokens.radiusSm,
                                            ),
                                            border: Border.all(
                                              color: color.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.more_time_rounded,
                                                size: 14,
                                                color: color,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Extend',
                                                style: theme.textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: color,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
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
}

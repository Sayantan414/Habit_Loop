import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/habit.dart';
import '../../widgets/confetti.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/habit_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/progress_ring.dart';
import '../add_habit/add_habit_screen.dart';
import '../habit_detail/habit_detail_screen.dart';
import 'completed_habits_screen.dart';

/// SCREEN 1 — Today dashboard.
///
/// Greeting header → daily completion ring → streak → today's habits.
/// Crossing 100% swaps the hero card to its celebration state and fires a
/// confetti burst exactly once, on the transition.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  Future<void> _check(Habit habit, int dayNumber) async {
    final wasAllDone = ref.read(todaySummaryProvider).allDone;
    final wasFinished = habit.isFinished;
    await ref.read(habitsProvider.notifier).toggleDay(habit, dayNumber);
    final nowAllDone = ref.read(todaySummaryProvider).allDone;
    final sound = ref.read(soundServiceProvider);

    if (!wasFinished && habit.isFinished) {
      sound.playAllDone();
      if (mounted) {
        Confetti.burst(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎉 Challenge Completed! "${habit.title}" moved to Completed.',
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else if (!wasAllDone && nowAllDone) {
      sound.playAllDone();
      if (mounted) Confetti.burst(context);
    } else {
      sound.playCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeHabitsProvider);
    final finished = ref.watch(finishedHabitsProvider);
    final paused = ref.watch(pausedHabitsProvider);
    final summary = ref.watch(todaySummaryProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gutter,
          AppTokens.space2,
          AppTokens.gutter,
          AppTokens.navClearance,
        ),
        children: [
          const _GreetingHeader(),
          const SizedBox(height: AppTokens.space5),
          _DailyProgressCard(summary: summary, habits: active),
          const SizedBox(height: AppTokens.space6),
          if (active.isEmpty && finished.isEmpty && paused.isEmpty)
            _EmptyState(onAdd: () => AddHabitSheet.show(context))
          else ...[
            if (active.isNotEmpty || finished.isNotEmpty)
              SectionHeader(
                title: "Today's habits",
                count: active.length,
                trailing: finished.isNotEmpty
                    ? Pressable(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CompletedHabitsScreen(),
                          ),
                        ),
                        scale: 0.92,
                        child: TagChip(
                          label: 'Completed (${finished.length}) ›',
                          color: AppPalette.of(context).success,
                          dense: true,
                        ),
                      )
                    : null,
              ),
            for (final habit in active)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.space3),
                child: HabitCard(
                  habit: habit,
                  onTap: () => _openDetail(habit),
                  onCheckIn: () => _check(habit, habit.todayDayNumber),
                ),
              ),
            if (paused.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space6),
              SectionHeader(
                title: 'Paused habits',
                count: paused.length,
              ),
              for (final habit in paused)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.space3),
                  child: GlassCard(
                    accent: AppPalette.of(context).warning,
                    padding: const EdgeInsets.all(AppTokens.space4),
                    onTap: () => _openDetail(habit),
                    child: Row(
                      children: [
                        Icon(
                          Icons.pause_circle_filled_rounded,
                          color: AppPalette.of(context).warning,
                          size: 24,
                        ),
                        const SizedBox(width: AppTokens.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                habit.title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Paused on ${DateFormat.MMMd().format(habit.pausedAt ?? DateTime.now())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppTokens.space2),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            foregroundColor: AppPalette.of(context).warning,
                            side: BorderSide(
                              color: AppPalette.of(context).warning.withValues(alpha: 0.5),
                            ),
                          ),
                          onPressed: () async {
                            await ref.read(habitsProvider.notifier).togglePause(habit);
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Resume'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  void _openDetail(Habit habit) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: habit.id)),
    );
  }
}

// ---------------------------------------------------------------- header

class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  static ({String text, IconData icon}) _greeting(int hour) {
    if (hour < 12) {
      return (text: 'Good morning', icon: Icons.wb_twilight_rounded);
    }
    if (hour < 17) {
      return (text: 'Good afternoon', icon: Icons.wb_sunny_rounded);
    }
    return (text: 'Good evening', icon: Icons.nightlight_round);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final greeting = _greeting(now.hour);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(greeting.icon, size: 15, color: p.warning),
                  const SizedBox(width: 6),
                  Text(
                    greeting.text,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Habit Loop', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 2),
              Text(
                DateFormat('EEEE, MMMM d').format(now),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: p.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const _ProfileAvatar(),
      ],
    );
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final habits = ref.watch(habitsProvider);
    final bestStreak = habits.fold<int>(
      0,
      (best, habit) => habit.currentStreak > best ? habit.currentStreak : best,
    );

    return Pressable(
      onTap: () => _showQuickStats(context, ref),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.isDark ? p.canvas : Colors.white,
          ),
          alignment: Alignment.center,
          child: bestStreak > 0
              ? Text('🔥', style: TextStyle(fontSize: p.isDark ? 19 : 19))
              : Icon(Icons.person_rounded, size: 22, color: p.textSecondary),
        ),
      ),
    );
  }

  void _showQuickStats(BuildContext context, WidgetRef ref) {
    FocusManager.instance.primaryFocus?.unfocus();
    final habits = ref.read(habitsProvider);
    final summary = ref.read(todaySummaryProvider);
    final bestStreak = habits.fold<int>(
      0,
      (best, habit) => habit.currentStreak > best ? habit.currentStreak : best,
    );
    final totalCheckIns = habits.fold<int>(
      0,
      (sum, habit) => sum + habit.completedDays.length,
    );

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.gutter,
              AppTokens.space4,
              AppTokens.gutter,
              AppTokens.space6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.strokeStrong,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.space5),
                Text('Your progress', style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppTokens.space4),
                Row(
                  children: [
                    _MiniStat(
                      label: 'Habits',
                      value: '${habits.length}',
                      color: p.accent,
                    ),
                    const SizedBox(width: AppTokens.space3),
                    _MiniStat(
                      label: 'Best streak',
                      value: '${bestStreak}d',
                      color: p.warning,
                    ),
                    const SizedBox(width: AppTokens.space3),
                    _MiniStat(
                      label: 'Check-ins',
                      value: '$totalCheckIns',
                      color: p.success,
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space4),
                Text(
                  summary.total == 0
                      ? 'Create a habit to start tracking your loop.'
                      : '${summary.done} of ${summary.total} habits done today.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: p.isDark ? 0.14 : 0.1),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: color,
                fontFeatures: AppTypography.tabular,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: p.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- daily progress card

class _DailyProgressCard extends StatelessWidget {
  const _DailyProgressCard({required this.summary, required this.habits});

  final TodaySummary summary;
  final List<Habit> habits;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    if (summary.total == 0) {
      return GlassCard(
        padding: const EdgeInsets.all(AppTokens.space5),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accent.withValues(alpha: p.isDark ? 0.16 : 0.12),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: p.accent,
                size: 24,
              ),
            ),
            const SizedBox(width: AppTokens.space4),
            Expanded(
              child: Text(
                'No habits running today — add one and your streak starts tonight.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    final ratio = summary.done / summary.total;
    final allDone = summary.allDone;
    final bestStreak = habits.fold<int>(
      0,
      (best, habit) => habit.currentStreak > best ? habit.currentStreak : best,
    );

    if (allDone) {
      return _CelebrationCard(streak: bestStreak, total: summary.total);
    }

    return GlassCard(
      padding: const EdgeInsets.all(AppTokens.space5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAILY PROGRESS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: p.textTertiary,
                  ),
                ),
                const SizedBox(height: AppTokens.space2),
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.displaySmall,
                    children: [
                      TextSpan(text: '${summary.done}'),
                      TextSpan(
                        text: ' / ${summary.total}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'habits completed today',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppTokens.space4),
                Wrap(
                  spacing: AppTokens.space2,
                  runSpacing: AppTokens.space2,
                  children: [
                    TagChip(
                      label: '$bestStreak day streak',
                      emoji: '🔥',
                      color: p.textSecondary,
                    ),
                    TagChip(
                      label: '${summary.total - summary.done} left',
                      icon: Icons.bolt_rounded,
                      color: p.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.space4),
          ProgressRing(
            value: ratio,
            size: 106,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(ratio * 100).round()}%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
                Text(
                  'done',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: p.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The 100% state — an eye-comfortable glass card that celebrates day completion.
class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({required this.streak, required this.total});

  final int streak;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(AppTokens.space5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ALL DONE TODAY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: p.textTertiary,
                  ),
                ),
                const SizedBox(height: AppTokens.space2),
                Text(
                  'Loop closed 🎉',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'All $total habits checked in. '
                  '${streak > 1 ? '$streak days and counting.' : 'Come back tomorrow.'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.space4),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.surfaceHigh,
              border: Border.all(color: p.strokeStrong, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.check_rounded, size: 24, color: p.accent),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- empty state

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.space8),
      child: Column(
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accent.withValues(alpha: p.isDark ? 0.14 : 0.1),
              border: Border.all(color: p.accent.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.loop_rounded, size: 46, color: p.accent),
          ),
          const SizedBox(height: AppTokens.space5),
          Text('Start your first loop', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppTokens.space2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space6),
            child: Text(
              'Pick a habit, choose a challenge length, and check in once a day. '
              'The streak does the rest.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppTokens.space5),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Create a habit'),
          ),
        ],
      ),
    );
  }
}



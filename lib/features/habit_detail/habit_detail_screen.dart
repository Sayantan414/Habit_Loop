import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/habit.dart';
import '../../widgets/app_background.dart';
import '../../widgets/confetti.dart';
import '../../widgets/extend_habit_dialog.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/reminder_times_picker.dart';
import '../../widgets/slip_dialog.dart';
import '../add_habit/add_habit_screen.dart';

/// SCREEN 2 — Habit detail and challenge grid.
///
/// The grid is the centrepiece: one cell per challenge day, with exactly one
/// interactive cell (today). Completed days are solid, missed days are muted
/// crosses, future days are locked, and today pulses until it's checked in.
class HabitDetailScreen extends ConsumerStatefulWidget {
  const HabitDetailScreen({super.key, required this.habitId});

  final String habitId;

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Habit? _find(List<Habit> habits) {
    for (final habit in habits) {
      if (habit.id == widget.habitId) return habit;
    }
    return null;
  }

  Future<void> _toggleToday(Habit habit) async {
    if (habit.isPaused) {
      _nudge('Habit is paused. Resume it to check in.');
      return;
    }
    final wasFinished = habit.isFinished;
    await ref.read(habitsProvider.notifier).toggleDay(habit, habit.todayDayNumber);
    ref.read(soundServiceProvider).playCheck();
    if (!wasFinished && habit.isFinished && mounted) {
      Confetti.burst(context);
    }
  }

  Future<void> _togglePause(Habit habit) async {
    final wasPaused = habit.isPaused;
    await ref.read(habitsProvider.notifier).togglePause(habit);
    if (mounted) {
      _nudge(wasPaused ? 'Habit resumed! Welcome back.' : 'Habit paused.');
    }
  }

  Future<void> _setReminders(Habit habit, List<int> times) async {
    final hadNone = habit.reminderTimes.isEmpty;
    await ref.read(habitsProvider.notifier).setReminderTimes(habit, times);
    if (hadNone && times.isNotEmpty) {
      await NotificationService.instance.requestPermissions();
    }
  }

  void _nudge(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final habit = _find(ref.watch(habitsProvider));
    if (habit == null) {
      return const Scaffold(body: Center(child: Text('Habit not found')));
    }

    final p = AppPalette.of(context);
    final color = AppAccents.of(context, habit.colorValue);
    final today = habit.todayDayNumber;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _DetailAppBar(
                title: habit.title,
                isPaused: habit.isPaused,
                isBad: habit.isBad,
                onEdit: () => AddHabitScreen.push(context, habit: habit),
                onTogglePause: () => _togglePause(habit),
                onDelete: () => _confirmDelete(habit),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.gutter,
                    AppTokens.space2,
                    AppTokens.gutter,
                    AppTokens.space8,
                  ),
                  children: [
                    _HeroHeader(habit: habit, color: color),
                    const SizedBox(height: AppTokens.space4),
                    _StatRow(habit: habit, color: color),
                    if (habit.isPaused) ...[
                      const SizedBox(height: AppTokens.space4),
                      _PausedBanner(
                        habit: habit,
                        onResume: () => _togglePause(habit),
                      ),
                    ],
                    if (habit.isFinished) ...[
                      const SizedBox(height: AppTokens.space4),
                      _CompletionBanner(
                        habit: habit,
                        color: color,
                        onExtend: () => showExtendHabitDialog(context, ref, habit),
                      ),
                    ],
                    if ((!habit.isFixed || habit.isStrict) &&
                        habit.missedDaysCount > 0 &&
                        !habit.isPaused &&
                        !habit.isFinished) ...[
                      const SizedBox(height: AppTokens.space4),
                      _ExtensionBanner(habit: habit),
                    ],
                    if (!habit.isFinished &&
                        !habit.isPaused &&
                        NotificationService.instance.isSupported) ...[
                      const SizedBox(height: AppTokens.space6),
                      const SectionHeader(title: 'Daily reminders'),
                      ReminderTimesPicker(
                        times: habit.reminderTimes,
                        color: color,
                        onChanged: (times) => _setReminders(habit, times),
                      ),
                    ],
                    const SizedBox(height: AppTokens.space6),
                    SectionHeader(
                      title: 'Challenge grid',
                      trailing: TagChip(
                        label: habit.isStrict
                            ? 'Strict mode'
                            : habit.isFixed
                            ? 'Fixed mode'
                            : 'Extended mode',
                        color: p.textSecondary,
                        dense: true,
                      ),
                    ),
                    _Legend(color: color, isBad: habit.isBad),
                    const SizedBox(height: AppTokens.space4),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: habit.effectiveTotalDays,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) {
                        final dayNumber = index + 1;
                        final isDone = habit.isDayCompleted(dayNumber);
                        final isToday = dayNumber == today;

                        return _DayCell(
                          dayNumber: dayNumber,
                          isDone: isDone,
                          isToday: isToday,
                          isMissed: habit.isDayMissed(dayNumber),
                          isBonus: dayNumber > habit.totalDays,
                          color: color,
                          // Pulsing would invite a tap, and for a bad habit
                          // a tap on today means logging a slip.
                          pulse: habit.isBad ? null : _pulse,
                          onTap: habit.isBad && !habit.isPaused
                              ? (dayNumber <= today
                                    ? () => toggleSlipWithConfirm(
                                        context,
                                        ref,
                                        habit,
                                        dayNumber,
                                      )
                                    : () => _nudge(
                                        'Day $dayNumber starts on '
                                        '${DateFormat.MMMd().format(habit.startDate.add(Duration(days: dayNumber - 1)))}.',
                                      ))
                              : habit.isPaused
                              ? () => _nudge('Habit is currently paused. Resume it to check in.')
                              : isToday
                                  ? () => _toggleToday(habit)
                                  : () => _nudge(
                                        dayNumber < today
                                            ? 'Day $dayNumber has passed — only today can be checked in.'
                                            : 'Day $dayNumber unlocks on '
                                                '${DateFormat.MMMd().format(habit.startDate.add(Duration(days: dayNumber - 1)))}.',
                                      ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit?'),
        content: Text(
          'This removes "${habit.title}" and all of its progress. '
          "This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.of(ctx).danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(habitsProvider.notifier).deleteHabit(habit.id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar({
    required this.title,
    required this.isPaused,
    this.isBad = false,
    required this.onEdit,
    required this.onTogglePause,
    required this.onDelete,
  });

  final String title;
  final bool isPaused;
  final bool isBad;
  final VoidCallback onEdit;
  final VoidCallback onTogglePause;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space3,
        AppTokens.space2,
        AppTokens.space3,
        AppTokens.space2,
      ),
      child: Row(
        children: [
          _CircleIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppTokens.space3),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: p.textSecondary),
            onSelected: (value) {
              if (value == 'pause') onTogglePause();
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (ctx) => [
              if (!isBad || isPaused)
                PopupMenuItem(
                  value: 'pause',
                  child: Row(
                    children: [
                      Icon(
                        isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_circle_outline_rounded,
                        size: 18,
                        color: isPaused ? p.success : p.warning,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isPaused ? 'Resume habit' : 'Pause habit',
                        style: TextStyle(
                          color: isPaused ? p.success : p.warning,
                        ),
                      ),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: p.textPrimary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Edit habit',
                      style: TextStyle(color: p.textPrimary),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: p.danger,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Delete habit',
                      style: TextStyle(color: p.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.isDark ? p.surfaceGlassHi : p.surface,
          border: Border.all(color: p.stroke),
        ),
        child: Icon(icon, size: 20, color: p.textPrimary),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.habit, required this.color});

  final Habit habit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return GlassCard(
      accent: color,
      padding: const EdgeInsets.all(AppTokens.space5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.isBad
                      ? '${habit.totalDays}-DAY QUIT'
                      : '${habit.totalDays}-DAY CHALLENGE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: AppTokens.space2),
                Text(
                  habit.title,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: AppTokens.space3),
                Wrap(
                  spacing: AppTokens.space3,
                  runSpacing: 6,
                  children: [
                    if (habit.isPaused)
                      _HeroMeta(
                        icon: Icons.pause_circle_filled_rounded,
                        label: 'PAUSED',
                        color: p.warning,
                        bold: true,
                      )
                    else
                      _HeroMeta(
                        icon: habit.isBad
                            ? Icons.shield_outlined
                            : Icons.local_fire_department_rounded,
                        label: habit.isBad
                            ? '${habit.currentStreak} days clean'
                            : '${habit.currentStreak} day streak',
                        color: p.warning,
                        bold: true,
                      ),
                    _HeroMeta(
                      icon: Icons.event_rounded,
                      label: DateFormat.yMMMd().format(habit.startDate),
                      color: p.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.space4),
          ProgressRing(
            value: habit.progress,
            size: 88,
            stroke: 8,
            color: color,
            trackColor: color.withValues(alpha: p.isDark ? 0.16 : 0.12),
            child: Text(
              '${(habit.progress * 100).round()}%',
              style: theme.textTheme.titleLarge?.copyWith(
                color: p.textPrimary,
                fontFeatures: AppTypography.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({
    required this.icon,
    required this.label,
    required this.color,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.habit, required this.color});

  final Habit habit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    if (habit.isBad) {
      return Row(
        children: [
          _StatChip(
            icon: Icons.shield_outlined,
            label: 'Clean days',
            value: '${habit.doneDaysCount}/${habit.totalDays}',
            color: color,
          ),
          const SizedBox(width: AppTokens.space3),
          _StatChip(
            icon: Icons.replay_rounded,
            label: 'Slips',
            value: '${habit.missedDaysCount}',
            color: p.textSecondary,
          ),
          const SizedBox(width: AppTokens.space3),
          _StatChip(
            icon: Icons.trending_up_rounded,
            label: 'Progress',
            value: '${(habit.progress * 100).round()}%',
            color: p.success,
          ),
        ],
      );
    }

    return Row(
      children: [
        _StatChip(
          icon: Icons.check_circle_rounded,
          label: 'Completed',
          value: '${habit.completedDays.length}/${habit.effectiveTotalDays}',
          color: color,
        ),
        const SizedBox(width: AppTokens.space3),
        _StatChip(
          icon: Icons.local_fire_department_rounded,
          label: 'Streak',
          value: '${habit.currentStreak}d',
          color: p.warning,
        ),
        const SizedBox(width: AppTokens.space3),
        _StatChip(
          icon: Icons.trending_up_rounded,
          label: 'Progress',
          value: '${(habit.progress * 100).round()}%',
          color: p.success,
        ),
      ],
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
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        radius: AppTokens.radiusMd,
        accent: color,
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFeatures: AppTypography.tabular,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: p.textTertiary,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Missed days extend the challenge by one day each — this states the penalty
/// plainly instead of letting the target silently drift.
class _ExtensionBanner extends StatelessWidget {
  const _ExtensionBanner({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final missed = habit.missedDaysCount;
    final days = missed == 1 ? 'day' : 'days';

    final String label;
    if (habit.isStrict) {
      label = 'Strict mode: Clean count restarted';
    } else {
      label = 'Extended by +$missed $days';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: p.isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: p.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.more_time_rounded, size: 16, color: p.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: p.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, this.isBad = false});

  final Color color;
  final bool isBad;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Wrap(
      spacing: AppTokens.space3,
      runSpacing: AppTokens.space2,
      children: [
        _LegendDot(color: color, label: isBad ? 'Clean' : 'Completed'),
        _LegendDot(
          color: p.danger.withValues(alpha: 0.5),
          label: isBad ? 'Slipped' : 'Missed',
        ),
        _LegendDot(color: color, label: 'Today', outlined: true),
        _LegendDot(
          color: p.isDark
              ? Colors.white.withValues(alpha: 0.12)
              : p.strokeStrong,
          label: isBad ? 'Upcoming' : 'Locked',
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.outlined = false,
  });

  final Color color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: outlined ? Colors.transparent : color,
            border: outlined ? Border.all(color: color, width: 2) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: p.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayNumber,
    required this.isDone,
    required this.isToday,
    required this.isMissed,
    required this.isBonus,
    required this.color,
    required this.pulse,
    required this.onTap,
  });

  final int dayNumber;
  final bool isDone;
  final bool isToday;
  final bool isMissed;

  /// True for the days appended by the missed-day penalty.
  final bool isBonus;
  final Color color;

  /// Null keeps today's cell still.
  final Animation<double>? pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    final Color fill;
    final Color border;
    Widget content;

    if (isDone) {
      fill = color;
      border = color;
      content = Icon(
        Icons.check_rounded,
        size: 20,
        color: p.isDark ? p.canvas : Colors.white,
      );
    } else if (isMissed) {
      fill = p.danger.withValues(alpha: p.isDark ? 0.1 : 0.07);
      border = p.danger.withValues(alpha: 0.3);
      content = Icon(
        Icons.close_rounded,
        size: 16,
        color: p.danger.withValues(alpha: 0.65),
      );
    } else if (isToday) {
      fill = color.withValues(alpha: p.isDark ? 0.18 : 0.12);
      border = color;
      content = Text(
        '$dayNumber',
        style: theme.textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontFeatures: AppTypography.tabular,
        ),
      );
    } else {
      fill = p.isDark
          ? Colors.white.withValues(alpha: 0.04)
          : p.surfaceHigh.withValues(alpha: 0.8);
      border = p.stroke;
      content = Text(
        '$dayNumber',
        style: theme.textTheme.titleMedium?.copyWith(
          color: p.textTertiary,
          fontFeatures: AppTypography.tabular,
        ),
      );
    }

    final cell = AnimatedContainer(
      duration: AppTokens.base,
      curve: AppTokens.emphasized,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: border, width: isToday ? 2 : 1),
      ),
      alignment: Alignment.center,
      child: content,
    );

    final semanticsLabel = 'Day $dayNumber'
        '${isDone ? ', completed' : isMissed ? ', missed' : isToday ? ', today' : ', locked'}'
        '${isBonus ? ', bonus day' : ''}';

    // Today breathes on its border rather than on a shadow — the one editable
    // cell still stands out, without anything on screen emitting light.
    final pulse = this.pulse;
    if (isToday && !isDone && pulse != null) {
      return Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Semantics(
          label: semanticsLabel,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(pulse.value);
              return Container(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  border: Border.all(
                    color: color.withValues(alpha: 0.4 + 0.6 * t),
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: content,
              );
            },
          ),
        ),
      );
    }

    return Pressable(
      onTap: onTap,
      scale: 0.94,
      haptic: true,
      child: Semantics(label: semanticsLabel, child: cell),
    );
  }
}

class _CompletionBanner extends StatelessWidget {
  const _CompletionBanner({
    required this.habit,
    required this.color,
    required this.onExtend,
  });

  final Habit habit;
  final Color color;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppTokens.space4),
      decoration: BoxDecoration(
        color: p.success.withValues(alpha: p.isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: p.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.success.withValues(alpha: 0.18),
                ),
                child: Icon(Icons.emoji_events_rounded, size: 20, color: p.success),
              ),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.isBad && habit.isFixed && habit.missedDaysCount > 0
                          ? 'Challenge finished'
                          : 'Challenge Completed! 🎉',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: p.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _completionText(habit),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onExtend,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(
                  color: color.withValues(alpha: 0.5),
                  width: 1.2,
                ),
                backgroundColor:
                    color.withValues(alpha: p.isDark ? 0.10 : 0.06),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
              ),
              icon: Icon(Icons.more_time_rounded, size: 18, color: color),
              label: Text(
                'Extend Challenge',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _completionText(Habit habit) {
  if (!habit.isBad) {
    return 'You successfully finished all ${habit.totalDays} days of this challenge.';
  }
  final slips = habit.missedDaysCount;
  if (slips == 0) {
    return 'You stayed clean for all ${habit.totalDays} days.';
  }
  if (habit.isFixed && !habit.isStrict) {
    return 'You made it: ${habit.doneDaysCount} of ${habit.totalDays} days clean. '
        'Every one of them counts.';
  }
  return 'You reached ${habit.totalDays} clean days, working through '
      '$slips ${slips == 1 ? 'slip' : 'slips'} along the way.';
}

class _PausedBanner extends StatelessWidget {
  const _PausedBanner({required this.habit, required this.onResume});

  final Habit habit;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final dateStr = habit.pausedAt != null
        ? DateFormat.MMMd().format(habit.pausedAt!)
        : 'recently';

    return GlassCard(
      accent: p.warning,
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.warning.withValues(alpha: 0.16),
                ),
                child: Icon(
                  Icons.pause_circle_filled_rounded,
                  size: 24,
                  color: p.warning,
                ),
              ),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Habit is Paused',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: p.warning,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paused on $dateStr. Missed days won\'t be counted while paused.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space3),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.warning,
                foregroundColor: Colors.black,
              ),
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Resume Habit'),
            ),
          ),
        ],
      ),
    );
  }
}



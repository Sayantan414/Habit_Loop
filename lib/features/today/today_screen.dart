import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../widgets/habit_card.dart';
import '../add_habit/add_habit_screen.dart';
import '../habit_detail/habit_detail_screen.dart';
import '../settings/settings_screen.dart';
import '../todo/todo_tab.dart';
import '../notes/notes_tab.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning 🌅';
    if (hour < 17) return 'Good afternoon ☀️';
    return 'Good evening 🌙';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                'Habit Loop',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
          bottom: TabBar(
            dividerColor: Colors.transparent,
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            tabs: const [
              Tab(
                icon: Icon(Icons.loop_rounded, size: 22),
              ),
              Tab(
                icon: Icon(Icons.check_box_outlined, size: 22),
              ),
              Tab(
                icon: Icon(Icons.sticky_note_2_outlined, size: 22),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _HabitsTab(),
            TodoTab(),
            NotesTab(),
          ],
        ),
      ),
    );
  }
}

class _HabitsTab extends ConsumerWidget {
  const _HabitsTab();

  void _openAddHabit(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddHabitScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeHabitsProvider);
    final finished = ref.watch(finishedHabitsProvider);
    final summary = ref.watch(todaySummaryProvider);
    final theme = Theme.of(context);

    if (active.isEmpty && finished.isEmpty) {
      return Scaffold(
        body: _EmptyState(onAdd: () => _openAddHabit(context)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openAddHabit(context),
          icon: const Icon(Icons.add_rounded, size: 22),
          label: const Text('Add habit', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _TodayBanner(summary: summary),
          const SizedBox(height: 24),
          if (active.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Active Habits',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${active.length}',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...active.map(
              (h) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: HabitCard(
                  habit: h,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: h.id)),
                  ),
                  onToggleToday: () async {
                    final wasAllDone = ref.read(todaySummaryProvider).allDone;
                    await ref.read(habitsProvider.notifier).toggleToday(h);
                    final nowAllDone = ref.read(todaySummaryProvider).allDone;
                    final sound = ref.read(soundServiceProvider);
                    if (!wasAllDone && nowAllDone) {
                      sound.playAllDone();
                    } else {
                      sound.playCheck();
                    }
                  },
                  onToggleDay: (dayNumber) async {
                    final wasAllDone = ref.read(todaySummaryProvider).allDone;
                    await ref.read(habitsProvider.notifier).toggleDay(h, dayNumber);
                    final nowAllDone = ref.read(todaySummaryProvider).allDone;
                    final sound = ref.read(soundServiceProvider);
                    if (!wasAllDone && nowAllDone) {
                      sound.playAllDone();
                    } else {
                      sound.playCheck();
                    }
                  },
                ),
              ),
            ),
          ],
          if (finished.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Completed Challenges 🎉',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${finished.length}',
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...finished.map(
              (h) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: HabitCard(
                  habit: h,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: h.id)),
                  ),
                  onToggleToday: () {},
                  onToggleDay: (dayNumber) async {
                    await ref.read(habitsProvider.notifier).toggleDay(h, dayNumber);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddHabit(context),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('Add habit', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _TodayBanner extends StatelessWidget {
  const _TodayBanner({required this.summary});
  final TodaySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (summary.total == 0) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Add a habit to kick off your streak journey!',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final allDone = summary.allDone;
    final ratio = summary.total == 0 ? 0.0 : summary.done / summary.total;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: allDone
              ? [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.2) ?? scheme.primary]
              : isDark
                  ? [scheme.surfaceContainerLow, scheme.surfaceContainer]
                  : [scheme.primary.withValues(alpha: 0.08), scheme.surfaceContainerLow],
        ),
        border: Border.all(
          color: allDone
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (allDone ? scheme.primary : Colors.black).withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allDone ? 'All Done Today! 🎉' : 'Daily Progress',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: allDone ? Colors.white : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allDone
                      ? 'You have completed all habits for today!'
                      : '${summary.done} of ${summary.total} habits completed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: allDone ? Colors.white.withValues(alpha: 0.85) : scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: (allDone ? Colors.white : scheme.primary).withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(allDone ? Colors.white : scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: allDone ? Colors.white.withValues(alpha: 0.2) : scheme.primary.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: allDone ? Colors.white : scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.loop_rounded, size: 64, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'No habits yet',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Start building positive routines day by day. Create your first challenge now!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add your first habit', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

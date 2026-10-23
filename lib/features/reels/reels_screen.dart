import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/reels_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/habit.dart';
import '../../widgets/glass_card.dart';
import '../add_habit/add_habit_screen.dart';
import '../habit_detail/habit_detail_screen.dart';
import 'reels_apps.dart';

/// SUB-SCREEN — Reels counter: today's count, the last week, and which apps
/// are watched.
///
/// Counting runs in a native accessibility service, so this screen re-reads
/// its numbers whenever the app comes back to the foreground (including the
/// return trip from Accessibility settings).
class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      await ref.read(reelsProvider.notifier).refresh();
      // The reminder is on by default; make sure it is allowed to show.
      if (ref.read(reelsProvider).remindEvery > 0) {
        await NotificationService.instance.requestPostPermission();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(reelsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reels = ref.watch(reelsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Reels Counter'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: !ReelsService.isSupported
            ? const _Message(text: 'The reels counter is available on Android only.')
            : reels.loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => ref.read(reelsProvider.notifier).refresh(),
                    child: ListView(
                      padding: const EdgeInsets.all(AppTokens.gutter),
                      children: [
                        if (!reels.serviceEnabled) ...[
                          const _EnableCard(),
                          const SizedBox(height: AppTokens.space5),
                        ],
                        _TodayCard(reels: reels),
                        const SizedBox(height: AppTokens.space5),
                        const SectionHeader(title: 'Reels habit'),
                        const _HabitShortcutCard(),
                        const SizedBox(height: AppTokens.space5),
                        const SectionHeader(title: 'Doomscrolling reminder'),
                        _ReminderCard(remindEvery: reels.remindEvery),
                        const SizedBox(height: AppTokens.space5),
                        const SectionHeader(title: 'Last 7 days'),
                        _WeekCard(reels: reels),
                        const SizedBox(height: AppTokens.space5),
                        SectionHeader(
                          title: 'Apps to track',
                          count: reels.selected.length,
                        ),
                        _AppsCard(reels: reels),
                        const SizedBox(height: AppTokens.space5),
                        _DetectionLogCard(log: reels.log),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Prominent disclosure shown before the user grants the permission, as
/// Google Play requires for accessibility services.
class _EnableCard extends StatelessWidget {
  const _EnableCard();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return GlassCard(
      accent: p.warning,
      highlighted: true,
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new_rounded, color: p.warning),
              const SizedBox(width: AppTokens.space2),
              Text('Turn on counting', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppTokens.space3),
          Text(
            'Habit Loop uses Android\'s Accessibility service to notice when '
            'you swipe to the next reel in the apps you choose below. It does '
            'not read your messages or what\'s on screen, works only in those '
            'apps, and nothing ever leaves your phone.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppTokens.space3),
          Text(
            'In settings, open "Installed apps" (or "Downloaded apps") → '
            'Habit Loop reels counter → turn it on.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: p.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.space4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                ReelsService.openAccessibilitySettings();
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open Accessibility settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.reels});

  final ReelsState reels;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayCounts = reels.countsOn(today);
    final total = reels.totalOn(today);
    final rows = reelsApps
        .where(
          (a) =>
              reels.selected.contains(a.packageName) ||
              (todayCounts[a.packageName] ?? 0) > 0,
        )
        .toList();

    return GlassCard(
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
              const SizedBox(width: AppTokens.space2),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  total == 1 ? 'reel today' : 'reels today',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              if (reels.serviceEnabled)
                TagChip(label: 'Counting', icon: Icons.circle, color: p.success),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: AppTokens.space3),
            Divider(height: 1, color: p.stroke),
            const SizedBox(height: AppTokens.space2),
            for (final app in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${app.name} ${app.surface}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${todayCounts[app.packageName] ?? 0}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFeatures: AppTypography.tabular,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Shortcut to the reels habit: opens the running one, or starts a new Quit
/// habit with reels tracking already switched on.
class _HabitShortcutCard extends ConsumerWidget {
  const _HabitShortcutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    Habit? running;
    for (final h in ref.watch(habitsProvider)) {
      if (h.isReelsHabit && !h.archived && !h.isFinished) {
        running = h;
        break;
      }
    }

    final title = running?.title ?? 'Turn this into a habit';
    final subtitle = running != null
        ? 'Day ${running.todayDayNumber.clamp(1, running.effectiveTotalDays)} '
              'of ${running.effectiveTotalDays} · '
              '${running.currentStreak} days clean'
        : 'Set a daily reels target for a number of days — '
              'slips are logged for you';

    return GlassCard(
      onTap: () {
        final habit = running;
        if (habit != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HabitDetailScreen(habitId: habit.id),
            ),
          );
        } else {
          AddHabitScreen.push(context, startAsReelsHabit: true);
        }
      },
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Row(
        children: [
          Icon(
            running != null ? Icons.shield_outlined : Icons.add_task_rounded,
            color: p.accent,
          ),
          const SizedBox(width: AppTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textTertiary),
        ],
      ),
    );
  }
}

/// The doomscrolling reminder: on/off and after how many reels in a row it
/// fires, typed into a number field.
class _ReminderCard extends ConsumerStatefulWidget {
  const _ReminderCard({required this.remindEvery});

  final int remindEvery;

  @override
  ConsumerState<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends ConsumerState<_ReminderCard> {
  static const _max = 999;

  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _initialText);
  }

  String get _initialText => widget.remindEvery > 0
      ? '${widget.remindEvery}'
      : '${ReelsNotifier.defaultRemindEvery}';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Saves the typed number as soon as it is valid.
  void _onChanged(String text) {
    final value = int.tryParse(text);
    final valid = value != null && value >= 1 && value <= _max;
    setState(() => _error = valid ? null : 'Enter a number from 1 to $_max');
    if (valid) ref.read(reelsProvider.notifier).setRemindEvery(value);
  }

  Future<void> _onToggle(bool on) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final typed = int.tryParse(_controller.text);
    final every = typed != null && typed >= 1 && typed <= _max
        ? typed
        : ReelsNotifier.defaultRemindEvery;
    await ref.read(reelsProvider.notifier).setRemindEvery(on ? every : 0);
    if (!on) return;

    _controller.text = '$every';
    setState(() => _error = null);
    final allowed = await NotificationService.instance.requestPostPermission();
    if (!allowed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked for Habit Loop. '
            'Allow them in system settings.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final enabled = widget.remindEvery > 0;

    return GlassCard(
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: p.warning),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Remind me', style: theme.textTheme.titleSmall),
                    Text(
                      'A nudge when you keep swiping reels without a break',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: _onToggle),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: AppTokens.space4),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              onChanged: _onChanged,
              decoration: InputDecoration(
                labelText: 'Remind me after this many reels',
                suffixText: 'reels',
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppTokens.space2),
            Text(
              'Counts reels in a row across your tracked apps. A break of '
              '5 minutes or more starts a fresh count.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.reels});

  final ReelsState reels;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final totals = days.map(reels.totalOn).toList();
    final maxTotal = totals.fold(0, (a, b) => a > b ? a : b);

    return GlassCard(
      padding: const EdgeInsets.all(AppTokens.space4),
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${totals[i]}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: p.textSecondary,
                        fontFeatures: AppTypography.tabular,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 18,
                      height: maxTotal == 0 ? 4 : 4 + 80 * totals[i] / maxTotal,
                      decoration: BoxDecoration(
                        color: i == days.length - 1
                            ? p.accent
                            : p.accent.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('E').format(days[i]).substring(0, 2),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: i == days.length - 1
                            ? p.textPrimary
                            : p.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppsCard extends ConsumerWidget {
  const _AppsCard({required this.reels});

  final ReelsState reels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final installed = reelsApps
        .where((a) => reels.installed.contains(a.packageName))
        .toList();

    if (installed.isEmpty) {
      return const GlassCard(
        child: _Message(
          text: 'None of the supported apps are installed on this phone.',
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final app in installed)
            CheckboxListTile(
              value: reels.selected.contains(app.packageName),
              onChanged: (value) {
                HapticFeedback.selectionClick();
                ref
                    .read(reelsProvider.notifier)
                    .setAppSelected(app.packageName, value ?? false);
              },
              title: Row(
                children: [
                  Flexible(
                    child: Text(app.name, style: theme.textTheme.titleSmall),
                  ),
                  if (app.beta) ...[
                    const SizedBox(width: AppTokens.space2),
                    TagChip(label: 'Beta', color: p.warning, dense: true),
                  ],
                ],
              ),
              subtitle: Text(
                'Counts swipes in ${app.surface} only',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.space4,
              AppTokens.space2,
              AppTokens.space4,
              AppTokens.space2,
            ),
            child: Text(
              'Scrolling the normal feed is not counted. Beta apps have not '
              'been checked on a real phone yet, so their counts may be off.',
              style: theme.textTheme.bodySmall?.copyWith(color: p.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the service saw scroll, one line per distinct container. Used to
/// check (and tune) whether reels and feeds are told apart correctly.
class _DetectionLogCard extends ConsumerWidget {
  const _DetectionLogCard({required this.log});

  final List<String> log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text('Detection log', style: theme.textTheme.titleSmall),
          subtitle: Text(
            'What the counter saw scroll — for checking accuracy',
            style: theme.textTheme.bodySmall,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTokens.space4,
            0,
            AppTokens.space4,
            AppTokens.space3,
          ),
          children: [
            if (log.isEmpty)
              Text(
                'Nothing yet. Turn counting on, then scroll in a selected app.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              for (final line in log)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: SelectableText(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                      color: line.endsWith('REELS')
                          ? p.success
                          : p.textSecondary,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => ref.read(reelsProvider.notifier).clearLog(),
                  child: const Text('Clear log'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/habit.dart';
import 'glass_card.dart';

/// Habit row on the Today dashboard.
///
/// Carries the habit's accent as a category tag, a seven-day mini strip, an
/// overall progress bar, and a single-tap check-in button. Tapping the card
/// opens the detail screen; tapping the circle checks today in place.
class HabitCard extends StatelessWidget {
  const HabitCard({
    super.key,
    required this.habit,
    required this.onTap,
    required this.onCheckIn,
  });

  final Habit habit;
  final VoidCallback onTap;

  /// Null for finished challenges — the button renders as a static trophy.
  final VoidCallback? onCheckIn;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final color = AppAccents.of(context, habit.colorValue);
    final done = habit.isCompletedToday;
    final dayNumber = habit.todayDayNumber.clamp(1, habit.effectiveTotalDays);

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Small subtle category dot (matching Notes card style)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 7, right: 10),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TagChip(
                          label: '${habit.currentStreak}d streak',
                          emoji: '🔥',
                          color: p.textSecondary,
                          dense: true,
                        ),
                        TagChip(
                          label:
                              'Day $dayNumber of ${habit.effectiveTotalDays}',
                          color: p.textSecondary,
                          dense: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CheckInButton(done: done, color: p.accent, onPressed: onCheckIn),
            ],
          ),
          const SizedBox(height: 12),
          _MiniDayStrip(habit: habit, color: color),
        ],
      ),
    );
  }
}

/// Row for a bad habit in the Today dashboard's "Avoiding" section.
///
/// There is nothing to check in: the day counts as clean unless a slip is
/// logged, so the only control is a quiet "Slipped" button (confirmed before
/// it counts). Once slipped, the same button undoes it.
class AvoidHabitCard extends StatelessWidget {
  const AvoidHabitCard({
    super.key,
    required this.habit,
    required this.onTap,
    required this.onSlip,
  });

  final Habit habit;
  final VoidCallback onTap;
  final VoidCallback onSlip;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final color = AppAccents.of(context, habit.colorValue);
    final slipped = habit.isSlippedToday;
    final streak = habit.currentStreak;
    final dayNumber = habit.todayDayNumber.clamp(1, habit.effectiveTotalDays);

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 7, right: 10),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TagChip(
                          label: '$streak ${streak == 1 ? 'day' : 'days'} clean',
                          icon: Icons.shield_outlined,
                          color: p.textSecondary,
                          dense: true,
                        ),
                        TagChip(
                          label:
                              'Day $dayNumber of ${habit.effectiveTotalDays}',
                          color: p.textSecondary,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      slipped
                          ? 'Slipped today — tomorrow is a fresh start.'
                          : 'Clean so far today',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: slipped ? p.textTertiary : p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onSlip,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: slipped ? p.textSecondary : p.danger,
                  side: BorderSide(
                    color: slipped
                        ? p.strokeStrong
                        : p.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(slipped ? 'Undo' : 'Slipped'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MiniDayStrip(habit: habit, color: color),
        ],
      ),
    );
  }
}

/// The single-tap check-in control.
///
/// On tap it pops (0.86 → 1.12 → 1.0) while a ring expands and fades outward,
/// so the confirmation is felt before the state even settles.
class CheckInButton extends StatefulWidget {
  const CheckInButton({
    super.key,
    required this.done,
    required this.color,
    required this.onPressed,
    this.size = 50,
  });

  final bool done;
  final Color color;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<CheckInButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 0.86), weight: 20),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.86,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 40,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 40),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0);
    widget.onPressed!.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final done = widget.done;
    final disabled = widget.onPressed == null;

    final btnSize = widget.size == 50 ? 40.0 : widget.size;

    return GestureDetector(
      onTap: disabled ? null : _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: btnSize + 8,
        height: btnSize + 8,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _BurstPainter(
                progress: _controller.value,
                color: p.accent,
              ),
              child: Center(
                child: Transform.scale(scale: _pop.value, child: child),
              ),
            );
          },
          child: AnimatedContainer(
            duration: AppTokens.base,
            curve: AppTokens.emphasized,
            width: btnSize,
            height: btnSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? (p.isDark
                        ? p.surfaceHigh
                        : p.accent.withValues(alpha: 0.12))
                  : Colors.transparent,
              border: Border.all(
                color: done ? p.accent : p.strokeStrong,
                width: 1.5,
              ),
            ),
            child: Icon(
              disabled
                  ? Icons.emoji_events_rounded
                  : done
                  ? Icons.check_rounded
                  : Icons.add_rounded,
              size: 20,
              color: done ? p.accent : p.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 * (0.6 + progress * 0.7);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - progress)
        ..color = color.withValues(alpha: (1 - progress) * 0.7),
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}

/// Seven-day mini progress indicator — yesterday-and-back plus today.
/// Day-wise small circular progress dots.
class _MiniDayStrip extends StatelessWidget {
  const _MiniDayStrip({required this.habit, required this.color});

  final Habit habit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final today = habit.todayDayNumber;
    final totalDays = habit.effectiveTotalDays;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var day = 1; day <= totalDays; day++) ...[
            _DayDot(
              day: day,
              isDone: habit.isDayCompleted(day),
              isToday: day == today,
              isMissed: habit.isDayMissed(day),
              color: color,
              palette: p,
            ),
            if (day != totalDays)
              _ConnectingLine(
                day: day,
                habit: habit,
                color: color,
                palette: p,
              ),
          ],
        ],
      ),
    );
  }
}

class _ConnectingLine extends StatelessWidget {
  const _ConnectingLine({
    required this.day,
    required this.habit,
    required this.color,
    required this.palette,
  });

  final int day;
  final Habit habit;
  final Color color;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final day1Done = habit.isDayCompleted(day);
    final day2Done = habit.isDayCompleted(day + 1);

    final day1Missed = habit.isDayMissed(day);
    final day2Missed = habit.isDayMissed(day + 1);

    final Color lineColor;

    if (day1Done && day2Done) {
      lineColor = color;
    } else if (day1Missed || day2Missed) {
      lineColor = Colors.transparent;
    } else {
      lineColor = color.withValues(alpha: palette.isDark ? 0.22 : 0.15);
    }

    return AnimatedContainer(
      duration: AppTokens.base,
      width: 8,
      height: 2.5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: lineColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.day,
    required this.isDone,
    required this.isToday,
    required this.isMissed,
    required this.color,
    required this.palette,
  });

  final int day;
  final bool isDone;
  final bool isToday;
  final bool isMissed;
  final Color color;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    const double size = 16;

    final Color? fill;
    final Border? border;

    if (isDone) {
      fill = color;
      border = null;
    } else if (isMissed) {
      fill = palette.isDark ? Colors.white24 : Colors.grey.shade400;
      border = null;
    } else if (isToday) {
      fill = color.withValues(alpha: 0.15);
      border = Border.all(color: color, width: 1.8);
    } else {
      fill = Colors.transparent;
      border = Border.all(
        color: palette.isDark
            ? Colors.white.withValues(alpha: 0.2)
            : palette.strokeStrong.withValues(alpha: 0.6),
        width: 1,
      );
    }

    return AnimatedContainer(
      duration: AppTokens.base,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: border,
      ),
      child: isDone
          ? const Center(
              child: Icon(
                Icons.check_rounded,
                size: 11,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

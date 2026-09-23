import 'package:flutter/material.dart';

import '../data/models/habit.dart';

/// A horizontal scrollable sequence of circular day indicators (1..effectiveTotalDays)
/// allowing users to view and check off today's day to maintain their streak.
class HabitStreakCircles extends StatefulWidget {
  const HabitStreakCircles({
    super.key,
    required this.habit,
    required this.onToggleDay,
  });

  final Habit habit;
  final ValueChanged<int> onToggleDay;

  @override
  State<HabitStreakCircles> createState() => _HabitStreakCirclesState();
}

class _HabitStreakCirclesState extends State<HabitStreakCircles> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Auto scroll to current day after layout built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && widget.habit.todayDayNumber > 3) {
        final targetOffset = ((widget.habit.todayDayNumber - 2) * 46.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final habit = widget.habit;
    final color = Color(habit.colorValue);
    final today = habit.todayDayNumber;

    return SizedBox(
      height: 48,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: habit.effectiveTotalDays,
        itemBuilder: (context, index) {
          final dayNumber = index + 1;
          final isCompleted = habit.isDayCompleted(dayNumber);
          final isToday = dayNumber == today;
          final isMissed = dayNumber < today && !isCompleted;
          final isFuture = dayNumber > today;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Day $dayNumber${isToday ? ' (Today)' : isCompleted ? ' (Completed)' : isMissed ? ' (Missed)' : ' (Upcoming)'}',
              child: Opacity(
                opacity: isToday || isCompleted ? 1.0 : 0.45,
                child: GestureDetector(
                  onTap: isToday ? () => widget.onToggleDay(dayNumber) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isCompleted
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color,
                                Color.lerp(color, Colors.black, 0.15) ?? color,
                              ],
                            )
                          : null,
                      color: isCompleted
                          ? null
                          : isMissed
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                              : isFuture
                                  ? theme.colorScheme.onSurface.withValues(alpha: 0.03)
                                  : color.withValues(alpha: 0.14),
                      border: Border.all(
                        color: isToday
                            ? color
                            : isCompleted
                                ? color
                                : isMissed
                                    ? theme.colorScheme.outlineVariant.withValues(alpha: 0.4)
                                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                        width: isToday ? 2.5 : 1.5,
                      ),
                      boxShadow: isCompleted
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              )
                            ]
                          : isToday
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                    ),
                    alignment: Alignment.center,
                    child: isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: Colors.white,
                          )
                        : Text(
                            '$dayNumber',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                              color: isToday
                                  ? color
                                  : isMissed
                                      ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

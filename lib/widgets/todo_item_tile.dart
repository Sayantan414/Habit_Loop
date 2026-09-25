import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/todo.dart';
import 'pressable.dart';

/// A single task row.
///
/// The whole row is the hit target for toggling. Completing a task animates
/// the checkbox fill, strikes the label through and drops it to 55% opacity,
/// so a finished task reads as "settled" without disappearing.
class TodoItemTile extends StatelessWidget {
  const TodoItemTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onDelete,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final done = todo.isCompleted;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space2),
      child: Dismissible(
        key: ValueKey(todo.id),
        direction: DismissDirection.endToStart,
        dismissThresholds: const {
          DismissDirection.endToStart: 0.65,
        },
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: p.danger.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          child: Icon(Icons.delete_outline_rounded, color: p.danger),
        ),
        child: Pressable(
          onTap: onToggle,
          scale: 0.985,
          child: AnimatedOpacity(
            opacity: done ? 0.55 : 1,
            duration: AppTokens.base,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.space4,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: p.isDark ? p.surfaceGlass : p.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(color: p.stroke),
                boxShadow: p.isDark
                    ? null
                    : [
                        BoxShadow(
                          color: p.shadow,
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                          spreadRadius: -6,
                        ),
                      ],
              ),
              child: Row(
                children: [
                  _TaskCheckbox(done: done, color: p.accent),
                  const SizedBox(width: AppTokens.space3),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: AppTokens.base,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        fontSize: 15,
                        color: done ? p.textSecondary : p.textPrimary,
                        fontWeight: done ? FontWeight.w400 : FontWeight.w500,
                        decoration: done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: p.textTertiary,
                        decorationThickness: 2,
                      ),
                      child: Text(todo.title),
                    ),
                  ),
                  const SizedBox(width: AppTokens.space2),
                  Pressable(
                    onTap: onDelete,
                    scale: 0.85,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: p.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskCheckbox extends StatelessWidget {
  const _TaskCheckbox({required this.done, required this.color});

  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return AnimatedContainer(
      duration: AppTokens.base,
      curve: AppTokens.springy,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: done ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: done ? color : p.strokeStrong,
          width: 2,
        ),
      ),
      child: AnimatedScale(
        scale: done ? 1 : 0,
        duration: AppTokens.base,
        curve: AppTokens.springy,
        child: Icon(
          Icons.check_rounded,
          size: 15,
          color: p.isDark ? p.canvas : Colors.white,
        ),
      ),
    );
  }
}

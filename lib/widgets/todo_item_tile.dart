import 'package:flutter/material.dart';

import '../data/models/todo.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final isDone = todo.isCompleted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isDone
            ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDone
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.2)
                : theme.colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.5),
            width: 1,
          ),
        ),
        child: ListTile(
        onTap: onToggle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? primary : Colors.transparent,
            border: Border.all(
              color: isDone ? primary : theme.colorScheme.outlineVariant,
              width: 2,
            ),
          ),
          child: isDone
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                )
              : null,
        ),
        title: Text(
          todo.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: isDone ? TextDecoration.lineThrough : TextDecoration.none,
            decorationColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            color: isDone
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                : theme.colorScheme.onSurface,
            fontWeight: isDone ? FontWeight.normal : FontWeight.w500,
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          onPressed: onDelete,
        ),
      ),
    ),
  );
}
}

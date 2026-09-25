import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/todo.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/todo_item_tile.dart';

/// SCREEN 4 — To-Do list.
///
/// Quick capture first: the entry bar sits at the top, keeps focus after
/// submit, and the new task lands directly beneath it. Completed tasks fold
/// into a collapsible section so they stay reviewable without adding noise.
class TodoTab extends ConsumerStatefulWidget {
  const TodoTab({super.key});

  @override
  ConsumerState<TodoTab> createState() => _TodoTabState();
}

class _TodoTabState extends ConsumerState<TodoTab> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _completedExpanded = true;
  Timer? _snackBarTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _snackBarTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(todosProvider.notifier).addTodo(text);
    _controller.clear();
    _focusNode.requestFocus();
    ref.read(soundServiceProvider).playCheck();
  }

  void _deleteWithUndo(Todo todo) {
    final notifier = ref.read(todosProvider.notifier);
    notifier.delete(todo.id);

    // Only show Undo SnackBar for active (uncompleted) tasks.
    if (todo.isCompleted) return;

    final p = AppPalette.of(context);
    final messenger = ScaffoldMessenger.of(context);

    _snackBarTimer?.cancel();
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(
          AppTokens.gutter,
          0,
          AppTokens.gutter,
          AppTokens.navClearance - 24,
        ),
        backgroundColor:
            p.isDark ? AppColors.darkSurfaceHigh : const Color(0xFF1E293B),
        content: Text(
          '"${todo.title}" deleted',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: p.isDark ? AppColors.darkTextPrimary : Colors.white,
            fontSize: 14,
          ),
        ),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: p.accent,
          onPressed: () {
            _snackBarTimer?.cancel();
            notifier.restoreTodo(todo);
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );

    _snackBarTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        messenger.hideCurrentSnackBar();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final active = ref.watch(activeTodosProvider);
    final completed = ref.watch(completedTodosProvider);
    final canSubmit = _controller.text.trim().isNotEmpty;

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
          Text('To-Do', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 2),
          Text(
            active.isEmpty
                ? 'Nothing pending — capture the next one below.'
                : '${active.length} task${active.length == 1 ? '' : 's'} left to clear',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppTokens.space5),

          // Quick entry bar.
          Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            decoration: BoxDecoration(
              color: p.isDark ? p.surfaceGlassHi : p.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              border: Border.all(
                color: canSubmit ? p.accent.withValues(alpha: 0.5) : p.stroke,
              ),
              boxShadow: [
                BoxShadow(
                  color: p.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                  spreadRadius: -8,
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Add a task…',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        color: p.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Pressable(
                  onTap: canSubmit ? _submit : null,
                  scale: 0.88,
                  child: AnimatedContainer(
                    duration: AppTokens.base,
                    curve: AppTokens.emphasized,
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                      color: canSubmit
                          ? p.accent
                          : (p.isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : p.surfaceHigh),
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: canSubmit
                          ? (p.isDark ? p.canvas : Colors.white)
                          : p.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space6),

          if (active.isEmpty && completed.isEmpty)
            const _EmptyTasks()
          else ...[
            if (active.isNotEmpty) ...[
              SectionHeader(title: 'Active tasks', count: active.length),
              for (final todo in active)
                TodoItemTile(
                  todo: todo,
                  onToggle: () async {
                    await ref.read(todosProvider.notifier).toggle(todo);
                    ref.read(soundServiceProvider).playCheck();
                  },
                  onDelete: () => _deleteWithUndo(todo),
                ),
            ],
            if (completed.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space5),
              SectionHeader(
                title: 'Completed',
                count: completed.length,
                color: p.success,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () =>
                          ref.read(todosProvider.notifier).clearCompleted(),
                      style: TextButton.styleFrom(
                        foregroundColor: p.danger,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Clear', style: TextStyle(fontSize: 12)),
                    ),
                    Pressable(
                      onTap: () => setState(
                        () => _completedExpanded = !_completedExpanded,
                      ),
                      scale: 0.85,
                      child: AnimatedRotation(
                        turns: _completedExpanded ? 0.5 : 0,
                        duration: AppTokens.base,
                        curve: AppTokens.emphasized,
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 22,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: Column(
                  children: [
                    for (final todo in completed)
                      TodoItemTile(
                        todo: todo,
                        onToggle: () =>
                            ref.read(todosProvider.notifier).toggle(todo),
                        onDelete: () => _deleteWithUndo(todo),
                      ),
                  ],
                ),
                secondChild: const SizedBox(width: double.infinity),
                crossFadeState: _completedExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: AppTokens.base,
                sizeCurve: AppTokens.emphasized,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.space8),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.success.withValues(alpha: p.isDark ? 0.14 : 0.1),
              border: Border.all(color: p.success.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.task_alt_rounded, size: 40, color: p.success),
          ),
          const SizedBox(height: AppTokens.space4),
          Text('Inbox zero', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppTokens.space2),
          Text(
            'Add a task above and it lands right here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

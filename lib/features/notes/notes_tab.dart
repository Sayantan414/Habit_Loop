import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/note.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import 'note_editor_screen.dart';

enum _NoteSort { recent, title }

/// SCREEN 5 — Notes.
///
/// A two-column masonry keeps short and long notes on screen together without
/// the dead space a uniform grid would leave. Columns are balanced by an
/// estimated card height, so the two sides stay level as notes are added.
class NotesTab extends ConsumerStatefulWidget {
  const NotesTab({super.key});

  @override
  ConsumerState<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<NotesTab> {
  final _searchController = TextEditingController();
  _NoteSort _sort = _NoteSort.recent;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openEditor([Note? note]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
    );
  }

  /// Rough card height, used only to decide which masonry column is shorter.
  static double _estimateHeight(Note note) {
    final preview = math.min(note.content.length, 240);
    return 96 + preview * 0.34 + math.min(note.title.length, 40) * 0.5;
  }

  static List<List<Note>> _columns(List<Note> notes, int count) {
    final columns = List.generate(count, (_) => <Note>[]);
    final heights = List<double>.filled(count, 0);
    for (final note in notes) {
      var shortest = 0;
      for (var i = 1; i < count; i++) {
        if (heights[i] < heights[shortest]) shortest = i;
      }
      columns[shortest].add(note);
      heights[shortest] += _estimateHeight(note);
    }
    return columns;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final query = ref.watch(searchQueryNotesProvider);
    final notes = [...ref.watch(filteredNotesProvider)];
    if (_sort == _NoteSort.title) {
      notes.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }

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
          Text('Notes', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 2),
          Text(
            '${notes.length} note${notes.length == 1 ? '' : 's'}'
            '${query.isEmpty ? '' : ' matching "$query"'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppTokens.space5),

          // Search + filter bar.
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: p.isDark ? p.surfaceGlassHi : p.surface,
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    border: Border.all(color: p.stroke),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 19, color: p.textTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style:
                              theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Search notes…',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                            hintStyle: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15,
                              color: p.textTertiary,
                            ),
                          ),
                          onChanged: (value) => ref
                              .read(searchQueryNotesProvider.notifier)
                              .state = value,
                        ),
                      ),
                      if (query.isNotEmpty)
                        Pressable(
                          onTap: () {
                            _searchController.clear();
                            ref
                                .read(searchQueryNotesProvider.notifier)
                                .state = '';
                          },
                          scale: 0.85,
                          child: Icon(Icons.close_rounded,
                              size: 18, color: p.textTertiary),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.space2),
              _SortButton(
                sort: _sort,
                onChanged: (value) => setState(() => _sort = value),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space5),

          if (notes.isEmpty)
            _EmptyNotes(
              searching: query.isNotEmpty,
              onAdd: () => _openEditor(),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columnCount = constraints.maxWidth > 620 ? 3 : 2;
                final columns = _columns(notes, columnCount);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < columnCount; i++) ...[
                      Expanded(
                        child: Column(
                          children: [
                            for (final note in columns[i])
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppTokens.space3,
                                ),
                                child: _NoteCard(
                                  note: note,
                                  onTap: () => _openEditor(note),
                                  onDelete: () => ref
                                      .read(notesProvider.notifier)
                                      .deleteNote(note.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (i != columnCount - 1)
                        const SizedBox(width: AppTokens.space3),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final _NoteSort sort;
  final ValueChanged<_NoteSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return PopupMenuButton<_NoteSort>(
      initialValue: sort,
      onSelected: onChanged,
      tooltip: 'Sort notes',
      itemBuilder: (_) => const [
        PopupMenuItem(value: _NoteSort.recent, child: Text('Recently updated')),
        PopupMenuItem(value: _NoteSort.title, child: Text('Title A–Z')),
      ],
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: p.isDark ? p.surfaceGlassHi : p.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: p.stroke),
        ),
        child: Icon(Icons.tune_rounded, size: 19, color: p.textSecondary),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Stable per-note accent so the wall of cards has rhythm without the user
  /// having to pick a color for every note.
  Color _accent(BuildContext context) {
    final index = note.id.hashCode.abs() % AppAccents.swatches.length;
    return AppAccents.resolve(
      AppAccents.swatches[index].id,
      Theme.of(context).brightness,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final accent = _accent(context);
    final hasContent = note.content.trim().isNotEmpty;

    return GlassCard(
      onTap: onTap,
      accent: accent,
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 8),
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              ),
              Expanded(
                child: Text(
                  note.title.isEmpty ? 'Untitled note' : note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 14.5),
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  tooltip: 'Note actions',
                  icon: Icon(Icons.more_horiz_rounded, color: p.textTertiary),
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                    if (value == 'open') onTap();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: p.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasContent) ...[
            const SizedBox(height: AppTokens.space2),
            Text(
              note.content.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ],
          const SizedBox(height: AppTokens.space3),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 12, color: p.textTertiary),
              const SizedBox(width: 4),
              Text(
                DateFormat('MMM d').format(note.updatedAt),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: p.textTertiary,
                  fontSize: 10.5,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Icon(Icons.north_east_rounded, size: 13, color: accent),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.searching, required this.onAdd});

  final bool searching;
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
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accentAlt.withValues(alpha: p.isDark ? 0.14 : 0.1),
              border: Border.all(color: p.accentAlt.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.edit_note_rounded,
              size: 42,
              color: p.accentAlt,
            ),
          ),
          const SizedBox(height: AppTokens.space4),
          Text(
            searching ? 'No matches' : 'A blank page',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppTokens.space2),
          Text(
            searching
                ? 'Try a different word or clear the search.'
                : 'Jot down thoughts, ideas and reminders.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (!searching) ...[
            const SizedBox(height: AppTokens.space5),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Write your first note'),
            ),
          ],
        ],
      ),
    );
  }
}

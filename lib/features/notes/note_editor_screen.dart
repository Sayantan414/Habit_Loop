import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/note.dart';
import '../../widgets/app_background.dart';
import '../../widgets/pressable.dart';

/// SCREEN 5b — Note editor.
///
/// Deliberately bare: no toolbar, no chrome competing with the text. The only
/// persistent UI is a thin status strip (saved state, timestamp, word count)
/// so the writer always knows the note is safe without pressing anything.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.note});

  final Note? note;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  Note? _currentNote;
  Timer? _debounceTimer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');

    _titleController.addListener(_onTextChanged);
    _contentController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // Keep the word count live while debouncing the actual write.
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), _autoSave);
  }

  Future<void> _autoSave() async {
    if (!mounted) return;
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      if (_currentNote != null) {
        final noteToDelete = _currentNote!;
        _currentNote = null;
        await ref.read(notesProvider.notifier).deleteNote(noteToDelete.id);
      }
      return;
    }

    final displayTitle = title.isEmpty ? 'Untitled note' : title;

    if (_currentNote == null) {
      setState(() => _isSaving = true);
      final newNote = await ref
          .read(notesProvider.notifier)
          .addNote(title: displayTitle, content: content);
      if (mounted) {
        setState(() {
          _currentNote = newNote;
          _isSaving = false;
        });
      }
    } else if (_currentNote!.title != displayTitle ||
        _currentNote!.content != content) {
      setState(() => _isSaving = true);
      await ref.read(notesProvider.notifier).updateNote(
            _currentNote!,
            title: displayTitle,
            content: content,
          );
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.removeListener(_onTextChanged);
    _contentController.removeListener(_onTextChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  int get _wordCount {
    final text = _contentController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  Future<void> _deleteNote() async {
    if (_currentNote == null) {
      Navigator.of(context).pop();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text("This note will be removed. This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.of(ctx).danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    final navigator = Navigator.of(context);
    final idToDelete = _currentNote!.id;
    _currentNote = null;
    await ref.read(notesProvider.notifier).deleteNote(idToDelete);
    navigator.pop();
  }

  void _copyNote() {
    final fullText =
        '${_titleController.text}\n\n${_contentController.text}'.trim();
    if (fullText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: fullText));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Note copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final updatedAt =
        _currentNote?.updatedAt ?? widget.note?.updatedAt ?? DateTime.now();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          _debounceTimer?.cancel();
          await _autoSave();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          child: SafeArea(
            child: Column(
              children: [
                // Minimal chrome: back, copy, delete.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _RoundAction(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      _RoundAction(
                        icon: Icons.copy_rounded,
                        onTap: _copyNote,
                      ),
                      if (_currentNote != null) ...[
                        const SizedBox(width: AppTokens.space2),
                        _RoundAction(
                          icon: Icons.delete_outline_rounded,
                          color: p.danger,
                          onTap: _deleteNote,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.gutter,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppTokens.space4),
                        TextField(
                          controller: _titleController,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: null,
                          style: theme.textTheme.displaySmall,
                          decoration: InputDecoration(
                            hintText: 'Title',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintStyle: theme.textTheme.displaySmall?.copyWith(
                              color: p.textTertiary.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTokens.space3),
                        Container(
                          height: 3,
                          width: 44,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusPill),
                            color: p.accent,
                          ),
                        ),
                        const SizedBox(height: AppTokens.space4),
                        Expanded(
                          child: TextField(
                            controller: _contentController,
                            textCapitalization: TextCapitalization.sentences,
                            maxLines: null,
                            expands: true,
                            autofocus: widget.note == null,
                            textAlignVertical: TextAlignVertical.top,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.65,
                              color: p.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Start writing…',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.65,
                                color: p.textTertiary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Status strip.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.gutter,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.stroke)),
                  ),
                  child: Row(
                    children: [
                      if (_isSaving) ...[
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.accent,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text('Saving…',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: p.accent)),
                      ] else if (_currentNote != null) ...[
                        Icon(Icons.cloud_done_rounded,
                            size: 14, color: p.success),
                        const SizedBox(width: 6),
                        Text(
                          'Saved ${DateFormat('MMM d · h:mm a').format(updatedAt)}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: p.textTertiary),
                        ),
                      ] else
                        Text(
                          'Autosaves as you type',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: p.textTertiary),
                        ),
                      const Spacer(),
                      Text(
                        '$_wordCount ${_wordCount == 1 ? 'word' : 'words'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: p.textSecondary,
                          fontFeatures: AppTypography.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

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
        child: Icon(icon, size: 19, color: color ?? p.textPrimary),
      ),
    );
  }
}

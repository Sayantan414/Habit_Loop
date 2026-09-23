import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/models/note.dart';

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
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _autoSave();
    });
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

    final displayTitle = title.isEmpty ? 'Untitled Note' : title;

    if (_currentNote == null) {
      setState(() => _isSaving = true);
      final newNote = await ref.read(notesProvider.notifier).addNote(
            title: displayTitle,
            content: content,
          );
      if (mounted) {
        setState(() {
          _currentNote = newNote;
          _isSaving = false;
        });
      }
    } else {
      if (_currentNote!.title != displayTitle || _currentNote!.content != content) {
        setState(() => _isSaving = true);
        await ref.read(notesProvider.notifier).updateNote(
              _currentNote!,
              title: displayTitle,
              content: content,
            );
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
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

  Future<void> _deleteNote() async {
    if (_currentNote == null) {
      Navigator.of(context).pop();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final idToDelete = _currentNote!.id;
      _currentNote = null;
      await ref.read(notesProvider.notifier).deleteNote(idToDelete);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEditing = _currentNote != null || widget.note != null;
    final updatedDate = _currentNote?.updatedAt ?? widget.note?.updatedAt ?? DateTime.now();
    final dateStr = DateFormat('MMM d, yyyy · h:mm a').format(updatedDate);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          _debounceTimer?.cancel();
          await _autoSave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isEditing ? 'Edit Note' : 'New Note',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy Note',
              onPressed: () {
                final fullText = '${_titleController.text}\n\n${_contentController.text}'.trim();
                if (fullText.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: fullText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note copied to clipboard')),
                  );
                }
              },
            ),
            if (_currentNote != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                tooltip: 'Delete Note',
                onPressed: _deleteNote,
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      dateStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (_isSaving)
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Saving...',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    else if (_currentNote != null)
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 13, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Saved',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Note Title',
                    hintStyle: theme.textTheme.headlineSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const Divider(height: 24),
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Start writing your note here...',
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        height: 1.5,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
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

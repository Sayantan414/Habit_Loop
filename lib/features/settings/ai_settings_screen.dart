import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/gemini_transcriber.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';

/// SUB-SCREEN — AI & voice: which recognizer dictation uses, and the user's
/// own Gemini API key.
///
/// Everything here is opt-in. Without a key nothing reaches the network
/// beyond what the phone's own recognizer does.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _keyController = TextEditingController();
  bool _checking = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) _keyController.text = text;
  }

  /// Checks the key with Google before keeping it. With no internet it's
  /// kept anyway, since it may well be fine.
  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _checking = true);
    final transcriber = GeminiTranscriber(apiKey: key);
    String message;
    try {
      final valid = await transcriber.checkKey();
      if (!valid) {
        message = "Google didn't accept this key. Copy it again from "
            'aistudio.google.com/apikey.';
      } else {
        await ref.read(geminiApiKeyProvider.notifier).save(key);
        _keyController.clear();
        message = 'Key saved. Gemini dictation is ready.';
      }
    } on TranscriptionException {
      await ref.read(geminiApiKeyProvider.notifier).save(key);
      _keyController.clear();
      message = "Key saved, but it couldn't be checked (no internet?).";
    } finally {
      transcriber.close();
    }
    if (!mounted) return;
    setState(() => _checking = false);
    _showMessage(message);
  }

  Future<void> _removeKey() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Gemini key?'),
        content: const Text(
          "Dictation goes back to the phone's recognizer. You can paste the "
          'key again any time.',
        ),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(geminiApiKeyProvider.notifier).remove();
    await ref.read(dictationEngineProvider.notifier).setEngine('phone');
  }

  void _selectEngine(String engine) {
    HapticFeedback.selectionClick();
    if (engine == 'gemini' && ref.read(geminiApiKeyProvider) == null) {
      _showMessage('Add your Gemini API key below first.');
      return;
    }
    ref.read(dictationEngineProvider.notifier).setEngine(engine);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final engine = ref.watch(dictationEngineProvider);
    final savedKey = ref.watch(geminiApiKeyProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('AI & voice'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gutter),
          children: [
            const SectionHeader(title: 'Dictation'),
            GlassCard(
              padding: const EdgeInsets.all(AppTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: 'phone',
                          icon: Icon(Icons.phone_android_rounded, size: 17),
                          label: Text('Phone'),
                        ),
                        ButtonSegment(
                          value: 'gemini',
                          icon: Icon(Icons.auto_awesome_rounded, size: 17),
                          label: Text('Gemini'),
                        ),
                      ],
                      selected: {engine},
                      onSelectionChanged: (s) => _selectEngine(s.first),
                    ),
                  ),
                  const SizedBox(height: AppTokens.space3),
                  Text(
                    engine == 'gemini'
                        ? 'Like a voice message: records the whole take, '
                            'then writes it all down when you stop. Best for '
                            'Bengali, mixed speech and long notes. Needs '
                            'internet.'
                        : "Android's built-in recognizer. Text appears as "
                            'you speak and it needs no key, but it may stop '
                            'and beep on pauses.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.space5),

            const SectionHeader(title: 'Gemini API key'),
            GlassCard(
              padding: const EdgeInsets.all(AppTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        savedKey == null
                            ? Icons.key_off_rounded
                            : Icons.verified_rounded,
                        size: 18,
                        color: savedKey == null ? p.textTertiary : p.success,
                      ),
                      const SizedBox(width: AppTokens.space2),
                      Expanded(
                        child: Text(
                          savedKey == null
                              ? 'No key saved'
                              : 'Saved · ${_masked(savedKey)}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (savedKey != null)
                        TextButton(
                          onPressed: _removeKey,
                          style: TextButton.styleFrom(
                            foregroundColor: p.danger,
                          ),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.space3),
                  TextField(
                    controller: _keyController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: savedKey == null
                          ? 'Paste your key (AIza…)'
                          : 'Paste a new key to replace it',
                      suffixIcon: IconButton(
                        tooltip: 'Paste',
                        icon: const Icon(Icons.content_paste_rounded),
                        onPressed: _paste,
                      ),
                    ),
                    onSubmitted: (_) => _saveKey(),
                  ),
                  const SizedBox(height: AppTokens.space3),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _saveKey,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(_checking ? 'Checking…' : 'Save key'),
                    ),
                  ),
                  const SizedBox(height: AppTokens.space3),
                  Text(
                    'Free key from aistudio.google.com/apikey. Stored only '
                    'on this phone, encrypted, and never included in '
                    'backups.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.space5),

            const SectionHeader(title: 'Privacy'),
            GlassCard(
              padding: const EdgeInsets.all(AppTokens.space4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: p.accentAlt),
                  const SizedBox(width: AppTokens.space3),
                  Expanded(
                    child: Text(
                      'With Gemini, each recording is sent to Google to be '
                      'turned into text, then deleted from Google straight '
                      'away. Nothing else from the app is sent. On the free '
                      'tier Google may use what you send to improve its '
                      'products, and people may review it, so use Phone '
                      'dictation for anything private.',
                      style: theme.textTheme.bodySmall,
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

  /// `AIza…a1b2`: enough to recognise the key, never the whole of it.
  static String _masked(String key) {
    if (key.length <= 8) return '••••';
    return '${key.substring(0, 4)}…${key.substring(key.length - 4)}';
  }
}

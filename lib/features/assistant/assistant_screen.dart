import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/screen_time.dart';
import '../../core/services/speech_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/dictation_button.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../settings/ai_settings_screen.dart';
import 'assistant_actions.dart';
import 'assistant_controller.dart';
import 'assistant_report.dart';

/// SCREEN — Assistant.
///
/// Type or speak a request; Gemini turns it into actions that the app
/// checks and runs itself, shown as glass cards with one Undo per request.
/// Deletes, new habits and sharing a note wait for a tap.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  static Future<void> open(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssistantScreen()));
  }

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final DictationController _dictation;

  /// The input as it was when dictation started; spoken words are laid
  /// into it at the cursor.
  TextEditingValue? _dictationBase;

  static const _examples = [
    'Add to-dos: wash car, exercise, read',
    'Mark "Morning walk" done for today',
    'Make a note "Trip plan": hotel, train tickets',
    'Create a habit to read 20 minutes a day',
    'Report for the last 2 weeks',
    'How long was I on Instagram this week?',
  ];

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _dictation = DictationController(ref.read(speechEngineProvider))
      ..addListener(_onDictation)
      ..onProblem = _showMessage
      ..onOfferDownload = _offerSpeechDownload;
  }

  @override
  void dispose() {
    _dictation.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    if (_dictation.isListening) {
      await _dictation.stop();
      return;
    }
    _dictationBase = _input.value;
    FocusManager.instance.primaryFocus?.unfocus();
    await _dictation.start(localeId: ref.read(dictationLocaleProvider));
  }

  void _onDictation() {
    final base = _dictationBase;
    if (base != null && _dictation.text.isNotEmpty) {
      _input.value = insertDictation(base, _dictation.text);
    }
    if (!_dictation.isListening) _dictationBase = null;
    if (mounted) setState(() {});
  }

  Future<void> _cycleDictationLocale() async {
    final locales = dictationLocales.keys.toList();
    final current = ref.read(dictationLocaleProvider);
    final next = locales[(locales.indexOf(current) + 1) % locales.length];
    await ref.read(dictationLocaleProvider.notifier).setLocale(next);
    await _dictation.switchLocale(next);
  }

  void _offerSpeechDownload(String localeId) {
    if (!mounted) return;
    final language = localeId.startsWith('bn') ? 'Bengali' : 'English';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Download $language for offline dictation that keeps '
            'listening through pauses?',
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Download',
            onPressed: () => _dictation.downloadLanguage(localeId),
          ),
        ),
      );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    if (_dictation.isListening) await _dictation.stop();
    final text = _input.text.trim();
    if (text.isEmpty || ref.read(assistantProvider.notifier).busy) return;
    _input.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    final sending = ref.read(assistantProvider.notifier).send(text);
    _scrollToEnd();
    await sending;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppTokens.base,
        curve: AppTokens.emphasized,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final turns = ref.watch(assistantProvider);
    final controller = ref.read(assistantProvider.notifier);
    final hasKey = ref.watch(geminiApiKeyProvider) != null;
    final busy = turns.any((t) => t.busy);
    final canSend = _input.text.trim().isNotEmpty && !busy;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _RoundAction(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: AppTokens.space3),
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: p.accentAlt,
                    ),
                    const SizedBox(width: 6),
                    Text('Assistant', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    if (turns.isNotEmpty && !busy)
                      _RoundAction(
                        icon: Icons.refresh_rounded,
                        onTap: controller.clear,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.gutter,
                    AppTokens.space4,
                    AppTokens.gutter,
                    AppTokens.space4,
                  ),
                  children: [
                    if (!hasKey) const _NoKeyCard(),
                    if (turns.isEmpty)
                      _Intro(
                        examples: _examples,
                        onPick: (text) => _input.value = TextEditingValue(
                          text: text,
                          selection: TextSelection.collapsed(
                            offset: text.length,
                          ),
                        ),
                      ),
                    for (final turn in turns)
                      _TurnView(turn: turn, controller: controller),
                  ],
                ),
              ),
              // Input bar.
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.space4,
                  AppTokens.space2,
                  AppTokens.space3,
                  AppTokens.space3,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.stroke)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        // Typing takes over from the mic.
                        onTap: () {
                          if (_dictation.isListening) _dictation.stop();
                        },
                        decoration: InputDecoration(
                          hintText: _dictation.isListening
                              ? 'Listening…'
                              : 'Ask or tell me what to do',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: DictationControls(
                        isListening: _dictation.isListening,
                        localeId: ref.watch(dictationLocaleProvider),
                        onMicTap: _toggleDictation,
                        onLocaleTap: _cycleDictationLocale,
                        onLocaleLongPress: () async =>
                            _showMessage(await _dictation.describe()),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Semantics(
                        button: true,
                        label: 'Send',
                        child: Pressable(
                          onTap: canSend ? _send : null,
                          child: AnimatedContainer(
                            duration: AppTokens.fast,
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: canSend ? p.accent : p.surfaceHigh,
                            ),
                            child: busy
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: p.accent,
                                    ),
                                  )
                                : Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 20,
                                    color: canSend
                                        ? (p.isDark ? p.canvas : Colors.white)
                                        : p.textTertiary,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoKeyCard extends StatelessWidget {
  const _NoKeyCard();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space4),
      child: GlassCard(
        accent: p.warning,
        highlighted: true,
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key_rounded, size: 18, color: p.warning),
                const SizedBox(width: AppTokens.space2),
                Text('Add your Gemini key', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppTokens.space2),
            Text(
              'The assistant runs on your own free key from Google AI '
              'Studio. It stays encrypted on this phone.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppTokens.space3),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
              ),
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Open AI & voice'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.examples, required this.onPick});

  final List<String> examples;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What should I do?', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppTokens.space2),
        Text(
          'Habits, to-dos, notes and settings, in Bengali or English. '
          'Everything I change can be undone.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppTokens.space4),
        Wrap(
          spacing: AppTokens.space2,
          runSpacing: AppTokens.space2,
          children: [
            for (final example in examples)
              Pressable(
                onTap: () => onPick(example),
                scale: 0.96,
                child: TagChip(label: example, color: p.accentAlt),
              ),
          ],
        ),
      ],
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn, required this.controller});

  final AssistantTurn turn;
  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The request, as a bubble on the right.
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.8,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: p.isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(color: p.accent.withValues(alpha: 0.25)),
              ),
              child: Text(turn.request, style: theme.textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          if (turn.reply.isNotEmpty) ...[
            Text(
              turn.reply,
              style: theme.textTheme.bodyMedium?.copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: AppTokens.space3),
          ],
          for (final item in turn.items) ...[
            _ItemCard(turn: turn, item: item, controller: controller),
            const SizedBox(height: AppTokens.space2),
          ],
          if (turn.error != null)
            _Notice(
              icon: Icons.cloud_off_rounded,
              text: turn.error!,
              color: p.danger,
            ),
          if (turn.busy)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: p.accentAlt,
                  ),
                ),
                const SizedBox(width: AppTokens.space2),
                Text('Thinking…', style: theme.textTheme.labelMedium),
              ],
            ),
          if (!turn.busy && turn.elapsed != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.space1),
              child: Text(
                [
                  if (turn.model != null) turn.model!,
                  '${(turn.elapsed!.inMilliseconds / 1000).toStringAsFixed(1)} s',
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: p.textTertiary,
                ),
              ),
            ),
          if (turn.canUndo)
            TextButton.icon(
              onPressed: () => controller.undo(turn),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Undo'),
            )
          else if (turn.undone)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.space1),
              child: TagChip(
                label: 'Undone',
                icon: Icons.undo_rounded,
                color: p.textTertiary,
                dense: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.turn,
    required this.item,
    required this.controller,
  });

  final AssistantTurn turn;
  final AssistantItem item;
  final AssistantController controller;

  static ({IconData icon, Color color}) _look(
    OutcomeKind kind,
    AppPalette p,
  ) => switch (kind) {
    OutcomeKind.habit => (icon: Icons.check_circle_rounded, color: p.success),
    OutcomeKind.slip => (icon: Icons.replay_rounded, color: p.warning),
    OutcomeKind.todo => (icon: Icons.checklist_rounded, color: p.accent),
    OutcomeKind.note => (icon: Icons.sticky_note_2_rounded, color: p.accentAlt),
    OutcomeKind.setting => (icon: Icons.tune_rounded, color: p.accent),
    OutcomeKind.report => (icon: Icons.insights_rounded, color: p.accentAlt),
    OutcomeKind.info => (
      icon: Icons.info_outline_rounded,
      color: p.textTertiary,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    final problem = item.problem;
    if (problem != null) {
      return _Notice(
        icon: Icons.block_rounded,
        text: problem,
        color: p.warning,
      );
    }
    final answer = item.answer;
    if (answer != null) {
      return Text(
        answer,
        style: theme.textTheme.bodyMedium?.copyWith(color: p.textPrimary),
      );
    }
    final outcome = item.outcome;
    if (outcome != null) {
      return _OutcomeCard(outcome: outcome, undone: turn.undone);
    }

    final action = item.action!;
    if (item.cancelled) {
      return _Notice(
        icon: Icons.close_rounded,
        text: '${AssistantActions.confirmTitle(action)} — cancelled',
        color: p.textTertiary,
      );
    }

    final isDelete = action is DeleteTodoAction || action is DeleteNoteAction;
    final look = switch (action) {
      AddHabitAction() => _look(OutcomeKind.habit, p),
      DeleteTodoAction() => (
        icon: Icons.delete_outline_rounded,
        color: p.danger,
      ),
      DeleteNoteAction() => (
        icon: Icons.delete_outline_rounded,
        color: p.danger,
      ),
      _ => _look(OutcomeKind.note, p),
    };

    return GlassCard(
      accent: look.color,
      highlighted: true,
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(look.icon, size: 18, color: look.color),
              const SizedBox(width: AppTokens.space2),
              Expanded(
                child: Text(
                  AssistantActions.confirmTitle(action),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (action is AddHabitAction) ...[
            const SizedBox(height: AppTokens.space1),
            Text(
              AssistantActions.describeDraft(action.draft),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (action is ReadNoteAction) ...[
            const SizedBox(height: AppTokens.space1),
            Text(
              'Only this note is sent. "Just show" opens it here without '
              'sending anything.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppTokens.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (action is ReadNoteAction)
                TextButton(
                  onPressed: turn.busy
                      ? null
                      : () => controller.showNoteOnly(turn, item),
                  child: const Text('Just show'),
                )
              else
                TextButton(
                  onPressed: () => controller.cancel(item),
                  child: const Text('Cancel'),
                ),
              const SizedBox(width: AppTokens.space2),
              FilledButton(
                style: isDelete
                    ? FilledButton.styleFrom(backgroundColor: p.danger)
                    : null,
                onPressed: turn.busy
                    ? null
                    : () => controller.confirm(turn, item),
                child: Text(switch (action) {
                  AddHabitAction() => 'Create',
                  ReadNoteAction() => 'Share',
                  _ => 'Delete',
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome, required this.undone});

  final ActionOutcome outcome;
  final bool undone;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final look = _ItemCard._look(outcome.kind, p);
    final takenBack = undone && outcome.undo != null;
    final report = outcome.report;

    return Opacity(
      opacity: takenBack ? 0.5 : 1,
      child: GlassCard(
        accent: look.color,
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(look.icon, size: 18, color: look.color),
                const SizedBox(width: AppTokens.space2),
                Expanded(
                  child: Text(
                    outcome.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      decoration: takenBack ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
            if (outcome.detail != null && outcome.detail!.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space2),
              Text(
                outcome.detail!,
                maxLines: 12,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ],
            for (final line in outcome.lines) ...[
              const SizedBox(height: AppTokens.space1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: look.color,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ],
            if (report != null) _ReportBody(report: report),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final AssistantReport report;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final habits = report.habits;
    final todos = report.todos;
    final screen = report.screenTime;

    String habitLine(HabitPeriod h) => h.isBad
        ? '${h.slips} slip${h.slips == 1 ? '' : 's'} · ${h.streak} days clean'
        : '${h.done}/${h.days} days · streak ${h.streak}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppTokens.space1),
        Text(
          report.days == 1
              ? DateFormat('EEEE, MMM d').format(report.to)
              : '${DateFormat('MMM d').format(report.from)} – '
                    '${DateFormat('MMM d').format(report.to)}',
          style: theme.textTheme.bodySmall,
        ),
        if (habits != null) ...[
          const _ReportHeading(icon: Icons.loop_rounded, title: 'Habits'),
          if (habits.isEmpty)
            Text(
              'No habits ran in this period.',
              style: theme.textTheme.bodySmall,
            ),
          for (final h in habits)
            _ReportRow(
              label: h.title,
              value: habitLine(h),
              color: h.isBad && h.slips > 0 ? p.warning : p.textSecondary,
            ),
        ],
        if (todos != null) ...[
          const _ReportHeading(icon: Icons.checklist_rounded, title: 'To-dos'),
          _ReportRow(label: 'Left to do', value: '${todos.open}'),
          _ReportRow(label: 'Done, still listed', value: '${todos.done}'),
          _ReportRow(
            label: 'Added in this period',
            value: '${todos.addedInPeriod}',
          ),
          if (todos.oldestOpen != null)
            _ReportRow(
              label: 'Oldest: ${todos.oldestOpen}',
              value: todos.oldestOpenDays == 0
                  ? 'today'
                  : '${todos.oldestOpenDays} days',
              color: todos.oldestOpenDays >= 7 ? p.warning : p.textSecondary,
            ),
        ],
        if (screen != null) ...[
          const _ReportHeading(
            icon: Icons.hourglass_bottom_rounded,
            title: 'Screen time',
          ),
          if (screen.trackedApps == 0)
            Text(
              'No screen-time habit is tracking any apps yet.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            _ReportRow(label: 'Total', value: _minutes(screen.total)),
            if (screen.byDay.length > 1) ...[
              _ReportRow(
                label: 'Per day',
                value: _minutes(screen.perDay.round()),
              ),
              _ReportRow(
                label: 'Busiest day',
                value:
                    '${DateFormat('EEE, MMM d').format(report.to.subtract(Duration(days: screen.byDay.length - 1 - screen.busiestDay)))}'
                    ' · ${_minutes(screen.byDay[screen.busiestDay])}',
              ),
            ],
            if (screen.previousTotal != null)
              _ReportRow(
                label: 'The ${report.days} days before',
                value: _minutes(screen.previousTotal!),
                color: screen.total > screen.previousTotal!
                    ? p.warning
                    : p.success,
              ),
            for (final e in screen.byApp.entries)
              _ReportRow(
                label: screen.labels[e.key] ?? e.key,
                value: _minutes(e.value),
              ),
            if (screen.byDay.length > 1) ...[
              const SizedBox(height: AppTokens.space2),
              _DayBars(values: screen.byDay, color: p.danger),
            ],
            if (report.days > screenTimeHistoryDays)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.space1),
                child: Text(
                  'Android keeps about the last $screenTimeHistoryDays days '
                  'of screen time.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// 95 → "1 h 35 min", 40 → "40 min".
String _minutes(int minutes) => minutes < 60
    ? '$minutes min'
    : '${minutes ~/ 60} h${minutes % 60 == 0 ? '' : ' ${minutes % 60} min'}';

class _ReportHeading extends StatelessWidget {
  const _ReportHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.space3, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: p.textTertiary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: p.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.space1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: AppTokens.space2),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color ?? p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small bar per day, oldest on the left, scaled to the busiest day.
class _DayBars extends StatelessWidget {
  const _DayBars({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final most = values.fold(0, (m, v) => v > m ? v : m);

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  height: most == 0 ? 2 : 2 + 38 * v / most,
                  decoration: BoxDecoration(
                    color: v == 0 ? p.stroke : color.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: AppTokens.space2),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

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
        child: Icon(icon, size: 19, color: p.textPrimary),
      ),
    );
  }
}

import '../../core/services/gemini_client.dart';
import '../../data/models/habit.dart';
import '../../data/models/note.dart';
import '../../data/models/todo.dart';
import 'assistant_tools.dart';
import 'assistant_report.dart';

enum AssistantSetting { theme, sound, vibration }

/// Everything the assistant may read or change, kept behind one interface
/// so every change still goes through the app's own notifiers (and a fake
/// stands in for them in tests).
abstract class AssistantStore {
  List<Habit> get habits;

  /// Open to-dos.
  List<Todo> get todos;

  /// Open and done, for reports.
  List<Todo> get allTodos;
  List<Note> get notes;

  Future<void> setHabitDays(
    Habit habit, {
    required List<int> completedDays,
    required List<int> slipDays,
  });
  Future<Habit> addHabit(HabitDraft draft);
  Future<void> deleteHabit(String id);

  Future<Todo> addTodo(String title);
  Future<void> toggleTodo(Todo todo);
  Future<void> deleteTodo(String id);
  Future<void> restoreTodo(Todo todo);

  Future<Note> addNote(String title, String content);
  Future<void> deleteNote(String id);
  Future<void> restoreNote(Note note);

  /// The setting's current value in the form [setSetting] takes:
  /// `light`/`dark`/`system` or `on`/`off`.
  String settingValue(AssistantSetting setting);
  Future<void> setSetting(AssistantSetting setting, String value);

  /// Whether this phone can read screen time at all (Android).
  bool get hasScreenTime;

  /// `{ 'yyyy-MM-dd': { package: minutes } }` for the apps screen-time
  /// habits track; empty without Usage access.
  Future<Map<String, Map<String, int>>> screenTimeUsage({required int days});

  /// Package name → app name, for showing screen time per app.
  Future<Map<String, String>> appLabels();
}

/// A habit the assistant proposes; created only after the user taps Create.
class HabitDraft {
  const HabitDraft({
    required this.title,
    required this.isBad,
    this.days = defaultDays,
    this.reminderTimes = const [],
  });

  static const defaultDays = 21;

  final String title;
  final bool isBad;
  final int days;

  /// Minutes after midnight, like [Habit.reminderTimes].
  final List<int> reminderTimes;
}

/// One validated tool call, ready to run.
sealed class AssistantAction {
  const AssistantAction();

  /// Deletes, new habits and sharing a note wait for the user's OK.
  bool get needsConfirmation => false;
}

class CompleteHabitAction extends AssistantAction {
  const CompleteHabitAction(this.habit);
  final Habit habit;
}

class LogSlipAction extends AssistantAction {
  const LogSlipAction(this.habit);
  final Habit habit;
}

class AddHabitAction extends AssistantAction {
  const AddHabitAction(this.draft);
  final HabitDraft draft;

  @override
  bool get needsConfirmation => true;
}

class AddTodosAction extends AssistantAction {
  const AddTodosAction(this.titles);
  final List<String> titles;
}

class CompleteTodoAction extends AssistantAction {
  const CompleteTodoAction(this.todo);
  final Todo todo;
}

class DeleteTodoAction extends AssistantAction {
  const DeleteTodoAction(this.todo);
  final Todo todo;

  @override
  bool get needsConfirmation => true;
}

class AddNoteAction extends AssistantAction {
  const AddNoteAction(this.title, this.content);
  final String title;
  final String content;
}

class DeleteNoteAction extends AssistantAction {
  const DeleteNoteAction(this.note);
  final Note note;

  @override
  bool get needsConfirmation => true;
}

/// Answering needs the note's text, which only leaves the phone if the
/// user agrees.
class ReadNoteAction extends AssistantAction {
  const ReadNoteAction(this.note);
  final Note note;

  @override
  bool get needsConfirmation => true;
}

class ReportAction extends AssistantAction {
  const ReportAction(this.days, this.topics);

  final int days;
  final Set<ReportTopic> topics;
}

class ChangeSettingAction extends AssistantAction {
  const ChangeSettingAction(this.setting, this.value);
  final AssistantSetting setting;
  final String value;
}

/// What a tool call turned into: an [action], or a [problem] to show.
typedef ParsedCall = ({AssistantAction? action, String? problem});

enum OutcomeKind { habit, slip, todo, note, setting, report, info }

/// The result card of one action, with the way to take it back.
class ActionOutcome {
  const ActionOutcome({
    required this.kind,
    required this.title,
    this.detail,
    this.lines = const [],
    this.undo,
    this.report,
  });

  final OutcomeKind kind;
  final String title;
  final String? detail;
  final List<String> lines;

  /// Null when there is nothing to undo (reports, no-ops).
  final Future<void> Function()? undo;
  final AssistantReport? report;
}

abstract final class AssistantActions {
  static const maxTodos = 20;
  static const maxTitle = 80;
  static const defaultReportDays = 7;

  /// Checks [call] against [context] and the tools [allowed] for this
  /// request. Nothing here trusts the model: ids must be ones it was given
  /// and values must make sense.
  static ParsedCall parse(
    GeminiCall call,
    AssistantContext context, {
    Iterable<String> allowed = AssistantTools.all,
  }) {
    if (!allowed.contains(call.name)) {
      return (action: null, problem: "That isn't something I can do here.");
    }
    final args = call.args;
    String? text(String key) {
      final value = args[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    AssistantAction? action;
    String? problem;
    switch (call.name) {
      case AssistantTools.completeHabit:
        final habit = context.habits[text('habit_id')];
        if (habit == null) {
          problem = "Couldn't find that habit among today's habits.";
        } else if (habit.isBad) {
          problem =
              '"${habit.title}" is a habit you\'re quitting, so there\'s '
              'nothing to check in.';
        } else {
          action = CompleteHabitAction(habit);
        }
      case AssistantTools.logSlip:
        final habit = context.habits[text('habit_id')];
        if (habit == null) {
          problem = "Couldn't find that habit among today's habits.";
        } else if (habit.isScreenTimeHabit) {
          problem = '"${habit.title}" tracks itself from your screen time.';
        } else if (!habit.isBad) {
          problem = 'Slips are only for habits you\'re quitting.';
        } else {
          action = LogSlipAction(habit);
        }
      case AssistantTools.addHabit:
        final title = text('title');
        if (title == null) {
          problem = 'The new habit needs a name.';
        } else {
          final days = args['days'];
          action = AddHabitAction(
            HabitDraft(
              title: _clip(title),
              isBad: args['kind'] == 'quit',
              days: days is num
                  ? days.toInt().clamp(1, 365)
                  : HabitDraft.defaultDays,
              // Quit habits have no reminders.
              reminderTimes: args['kind'] == 'quit'
                  ? const []
                  : _reminders(args['reminder_times']),
            ),
          );
        }
      case AssistantTools.addTodos:
        final raw = args['titles'];
        final titles = [
          if (raw is List)
            for (final t in raw)
              if (t is String && t.trim().isNotEmpty) _clip(t.trim()),
        ];
        if (titles.isEmpty) {
          problem = 'No to-dos to add.';
        } else {
          action = AddTodosAction(titles.take(maxTodos).toList());
        }
      case AssistantTools.completeTodo:
      case AssistantTools.deleteTodo:
        final todo = context.todos[text('todo_id')];
        if (todo == null) {
          problem = "Couldn't find that to-do.";
        } else {
          action = call.name == AssistantTools.completeTodo
              ? CompleteTodoAction(todo)
              : DeleteTodoAction(todo);
        }
      case AssistantTools.addNote:
        final content = text('content');
        if (content == null) {
          problem = 'The note was empty.';
        } else {
          action = AddNoteAction(_clip(text('title') ?? ''), content);
        }
      case AssistantTools.deleteNote:
      case AssistantTools.readNote:
        final note = context.notes[text('note_id')];
        if (note == null) {
          problem = "Couldn't find that note.";
        } else {
          action = call.name == AssistantTools.deleteNote
              ? DeleteNoteAction(note)
              : ReadNoteAction(note);
        }
      case AssistantTools.report:
        final days = args['days'];
        final raw = args['topics'];
        final topics = {
          if (raw is List)
            for (final t in raw)
              for (final topic in ReportTopic.values)
                // The tool spells screenTime the API's way, as screen_time.
                if ((topic == ReportTopic.screenTime
                        ? 'screen_time'
                        : topic.name) ==
                    t)
                  topic,
        };
        action = ReportAction(
          days is num
              ? days.toInt().clamp(1, AssistantReport.maxDays)
              : defaultReportDays,
          topics.isEmpty ? ReportTopic.values.toSet() : topics,
        );
      case AssistantTools.changeSetting:
        final parsed = _setting(text('setting'), text('value'));
        if (parsed == null) {
          problem = "I can't set that.";
        } else {
          action = ChangeSettingAction(parsed.$1, parsed.$2);
        }
      default:
        problem = "That isn't something I can do here.";
    }
    return (action: action, problem: problem);
  }

  /// Runs [action] through [store] and says how to undo it.
  static Future<ActionOutcome> run(
    AssistantStore store,
    AssistantAction action, {
    DateTime? now,
  }) async {
    switch (action) {
      case CompleteHabitAction(:final habit):
        final day = habit.todayDayNumber;
        if (habit.completedDays.contains(day)) {
          return ActionOutcome(
            kind: OutcomeKind.info,
            title: '"${habit.title}" was already done today',
          );
        }
        final before = habit.completedDays.toList();
        final slips = habit.slipDays.toList();
        await store.setHabitDays(
          habit,
          completedDays: [...before, day],
          slipDays: slips,
        );
        return ActionOutcome(
          kind: OutcomeKind.habit,
          title: 'Checked in "${habit.title}"',
          detail: 'Day $day',
          undo: () =>
              store.setHabitDays(habit, completedDays: before, slipDays: slips),
        );

      case LogSlipAction(:final habit):
        final day = habit.todayDayNumber;
        if (habit.slipDays.contains(day)) {
          return ActionOutcome(
            kind: OutcomeKind.info,
            title: 'A slip was already logged today on "${habit.title}"',
          );
        }
        final done = habit.completedDays.toList();
        final before = habit.slipDays.toList();
        await store.setHabitDays(
          habit,
          completedDays: done,
          slipDays: [...before, day]..sort(),
        );
        return ActionOutcome(
          kind: OutcomeKind.slip,
          title: 'Logged a slip on "${habit.title}"',
          detail: 'Day $day',
          undo: () =>
              store.setHabitDays(habit, completedDays: done, slipDays: before),
        );

      case AddHabitAction(:final draft):
        final habit = await store.addHabit(draft);
        return ActionOutcome(
          kind: OutcomeKind.habit,
          title: 'Created "${habit.title}"',
          detail: describeDraft(draft),
          undo: () => store.deleteHabit(habit.id),
        );

      case AddTodosAction(:final titles):
        final added = <Todo>[];
        for (final title in titles) {
          added.add(await store.addTodo(title));
        }
        return ActionOutcome(
          kind: OutcomeKind.todo,
          title: added.length == 1
              ? 'Added a to-do'
              : 'Added ${added.length} to-dos',
          lines: titles,
          undo: () async {
            for (final todo in added) {
              await store.deleteTodo(todo.id);
            }
          },
        );

      case CompleteTodoAction(:final todo):
        if (todo.isCompleted) {
          return ActionOutcome(
            kind: OutcomeKind.info,
            title: '"${todo.title}" was already done',
          );
        }
        await store.toggleTodo(todo);
        return ActionOutcome(
          kind: OutcomeKind.todo,
          title: 'Done: "${todo.title}"',
          undo: () async {
            if (todo.isCompleted) await store.toggleTodo(todo);
          },
        );

      case DeleteTodoAction(:final todo):
        await store.deleteTodo(todo.id);
        return ActionOutcome(
          kind: OutcomeKind.todo,
          title: 'Deleted "${todo.title}"',
          undo: () => store.restoreTodo(todo),
        );

      case AddNoteAction(:final title, :final content):
        final note = await store.addNote(title, content);
        return ActionOutcome(
          kind: OutcomeKind.note,
          title: title.isEmpty ? 'Created a note' : 'Created "$title"',
          detail: content,
          undo: () => store.deleteNote(note.id),
        );

      case DeleteNoteAction(:final note):
        await store.deleteNote(note.id);
        return ActionOutcome(
          kind: OutcomeKind.note,
          title: 'Deleted "${noteTitle(note)}"',
          undo: () => store.restoreNote(note),
        );

      case ReadNoteAction(:final note):
        // Shown on the phone only; nothing is sent.
        return ActionOutcome(
          kind: OutcomeKind.note,
          title: noteTitle(note),
          detail: note.content,
        );

      case ReportAction(:final days, :final topics):
        final wantsScreenTime =
            topics.contains(ReportTopic.screenTime) && store.hasScreenTime;
        final report = AssistantReport.compute(
          days: days,
          topics: topics,
          habits: store.habits,
          todos: store.allTodos,
          screenTimeUsage: wantsScreenTime
              ? await store.screenTimeUsage(
                  days: AssistantReport.screenTimeDaysNeeded(days),
                )
              : const {},
          appLabels: wantsScreenTime ? await store.appLabels() : const {},
          hasScreenTime: store.hasScreenTime,
          now: now,
        );
        return ActionOutcome(
          kind: OutcomeKind.report,
          title: reportTitle(days),
          report: report,
        );

      case ChangeSettingAction(:final setting, :final value):
        final before = store.settingValue(setting);
        await store.setSetting(setting, value);
        return ActionOutcome(
          kind: OutcomeKind.setting,
          title: describeSetting(setting, value),
          undo: () => store.setSetting(setting, before),
        );
    }
  }

  /// One line for a confirmation card.
  static String confirmTitle(AssistantAction action) => switch (action) {
    AddHabitAction(:final draft) => 'New habit: "${draft.title}"',
    DeleteTodoAction(:final todo) => 'Delete to-do "${todo.title}"?',
    DeleteNoteAction(:final note) => 'Delete note "${noteTitle(note)}"?',
    ReadNoteAction(:final note) =>
      'Share "${noteTitle(note)}" with Gemini to answer?',
    _ => '',
  };

  static String describeDraft(HabitDraft draft) {
    final kind = draft.isBad ? 'Quit' : 'Build';
    final reminders = draft.reminderTimes.isEmpty
        ? ''
        : ' · reminders ${draft.reminderTimes.map(_hhmm).join(', ')}';
    return '$kind · ${draft.days} days$reminders';
  }

  static String describeSetting(AssistantSetting setting, String value) =>
      switch (setting) {
        AssistantSetting.theme => 'Theme set to $value',
        AssistantSetting.sound => 'Sounds turned $value',
        AssistantSetting.vibration => 'Vibration turned $value',
      };

  static String reportTitle(int days) => switch (days) {
    1 => 'Today',
    7 => 'Your last 7 days',
    _ when days % 7 == 0 => 'Your last ${days ~/ 7} weeks',
    _ => 'Your last $days days',
  };

  static String noteTitle(Note note) =>
      note.title.trim().isEmpty ? 'Untitled note' : note.title.trim();

  static String _clip(String s) =>
      s.length <= maxTitle ? s : '${s.substring(0, maxTitle - 1)}…';

  static List<int> _reminders(Object? raw) {
    if (raw is! List) return const [];
    final minutes = <int>{};
    for (final item in raw) {
      final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('$item'.trim());
      if (match == null) continue;
      final h = int.parse(match[1]!);
      final m = int.parse(match[2]!);
      if (h < 24 && m < 60) minutes.add(h * 60 + m);
    }
    return minutes.toList()..sort();
  }

  static (AssistantSetting, String)? _setting(String? name, String? value) {
    final v = value?.toLowerCase();
    if (v == null) return null;
    String? onOff() => switch (v) {
      'on' || 'true' || 'enable' || 'enabled' => 'on',
      'off' || 'false' || 'disable' || 'disabled' => 'off',
      _ => null,
    };
    switch (name) {
      case 'theme':
        return const ['light', 'dark', 'system'].contains(v)
            ? (AssistantSetting.theme, v)
            : null;
      case 'sound':
        final s = onOff();
        return s == null ? null : (AssistantSetting.sound, s);
      case 'vibration':
        final s = onOff();
        return s == null ? null : (AssistantSetting.vibration, s);
      default:
        return null;
    }
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

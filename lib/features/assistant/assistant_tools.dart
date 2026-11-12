import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/models/habit.dart';
import '../../data/models/note.dart';
import '../../data/models/todo.dart';

/// Every tool the assistant may ask for. delete_habit is left out on
/// purpose: losing a habit's history is too costly for a misheard word.
abstract final class AssistantTools {
  static const completeHabit = 'complete_habit';
  static const logSlip = 'log_slip';
  static const addHabit = 'add_habit';
  static const addTodos = 'add_todos';
  static const completeTodo = 'complete_todo';
  static const deleteTodo = 'delete_todo';
  static const addNote = 'add_note';
  static const deleteNote = 'delete_note';
  static const readNote = 'read_note';
  static const report = 'report';
  static const changeSetting = 'change_setting';

  static const all = [
    completeHabit,
    logSlip,
    addHabit,
    addTodos,
    completeTodo,
    deleteTodo,
    addNote,
    deleteNote,
    readNote,
    report,
    changeSetting,
  ];

  static Map<String, dynamic> _tool(
    String name,
    String description, [
    Map<String, dynamic> properties = const {},
    List<String> required = const [],
  ]) => {
    'type': 'function',
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    },
  };

  static const _id = {'type': 'string'};

  static final _declarations = <String, Map<String, dynamic>>{
    completeHabit: _tool(
      completeHabit,
      'Check in a habit the user is building, for today.',
      {'habit_id': _id},
      ['habit_id'],
    ),
    logSlip: _tool(
      logSlip,
      'Log a slip today on a habit the user is quitting (type "quit"). '
      'Never for type "screen_time": those track themselves.',
      {'habit_id': _id},
      ['habit_id'],
    ),
    addHabit: _tool(
      addHabit,
      'Propose a new habit. The user sees a preview and taps Create.',
      {
        'title': {'type': 'string', 'description': 'Short, e.g. "Read 20 min"'},
        'kind': {
          'type': 'string',
          'enum': ['build', 'quit'],
        },
        'days': {
          'type': 'integer',
          'description': 'Challenge length. 21 if the user does not say.',
        },
        'reminder_times': {
          'type': 'array',
          'items': {'type': 'string', 'description': '24-hour HH:mm'},
          'description': 'Build habits only; quit habits have no reminders.',
        },
      },
      ['title', 'kind'],
    ),
    addTodos: _tool(
      addTodos,
      'Add one or more to-dos, each a short task. When they belong to a '
      'named project, start each title with the project name and a colon, '
      'e.g. "SNTMS: Fix the Signal Failure add button".',
      {
        'titles': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      ['titles'],
    ),
    completeTodo: _tool(
      completeTodo,
      'Mark an open to-do as done.',
      {'todo_id': _id},
      ['todo_id'],
    ),
    deleteTodo: _tool(
      deleteTodo,
      'Delete a to-do. The user confirms first.',
      {'todo_id': _id},
      ['todo_id'],
    ),
    addNote: _tool(
      addNote,
      'Create a note. Tidy what the user said into clear, structured text '
      '(short lines, "- " bullets where it helps) without adding facts.',
      {
        'title': {'type': 'string'},
        'content': {'type': 'string'},
      },
      ['title', 'content'],
    ),
    deleteNote: _tool(
      deleteNote,
      'Delete a note. The user confirms first.',
      {'note_id': _id},
      ['note_id'],
    ),
    readNote: _tool(
      readNote,
      "Needed to answer anything about a note's contents. The user decides "
      'whether to share it.',
      {'note_id': _id},
      ['note_id'],
    ),
    report: _tool(
      report,
      'Show a report worked out on the phone, for questions like "how did '
      'my week go", "how many to-dos are left" or "how long was I on '
      'Instagram this week". Screen time covers only the apps tracked by '
      'screen-time habits, and only about the last 7 days.',
      {
        'topics': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['habits', 'todos', 'screen_time'],
          },
          'description':
              'What to cover; all three if the user asks for a '
              'general report.',
        },
        'days': {
          'type': 'integer',
          'description':
              'How many days back, today included: today = 1, '
              'a week = 7, "last 13 days" = 13, two weeks = 14, four weeks '
              '= 28, a month = 30. 7 if the user does not say.',
        },
      },
      ['topics'],
    ),
    changeSetting: _tool(
      changeSetting,
      'Change an app setting. theme: light, dark or system. sound and '
      'vibration: on or off.',
      {
        'setting': {
          'type': 'string',
          'enum': ['theme', 'sound', 'vibration'],
        },
        'value': {'type': 'string'},
      },
      ['setting', 'value'],
    ),
  };

  /// Declarations for [names], in the API's function tool format.
  static List<Map<String, dynamic>> declarations(Iterable<String> names) => [
    for (final name in names) _declarations[name]!,
  ];

  static String systemInstruction(String replyLanguage) => '''
You are the assistant inside Habit Loop, a habit, to-do and notes app.
Turn the user's request into tool calls. Several actions in one request mean several calls.
Use only ids from the context. If something is unclear or not in the context, ask briefly instead of guessing.
The app runs the tools and shows their results itself, so never claim an action is done; just add a short reply when it helps.
Answer questions about habits, to-dos and note titles from the context.
Reply in $replyLanguage, in one or two short sentences. The user often mixes Bengali and English.''';
}

/// What one request may see: running habits, open to-dos and note titles,
/// each under a short alias (h1, t1, n1) so the model can't invent ids and
/// real ids never leave the phone.
class AssistantContext {
  AssistantContext({
    required List<Habit> habits,
    required List<Todo> todos,
    required List<Note> notes,
    DateTime? now,
  }) : now = now ?? DateTime.now() {
    for (final h in habits) {
      final running =
          !h.archived && !h.isPaused && !h.isFinished && h.isActiveToday;
      if (running) this.habits['h${this.habits.length + 1}'] = h;
    }
    for (final t in todos) {
      if (!t.isCompleted) this.todos['t${this.todos.length + 1}'] = t;
    }
    for (final n in notes) {
      this.notes['n${this.notes.length + 1}'] = n;
    }
  }

  final DateTime now;
  final habits = <String, Habit>{};
  final todos = <String, Todo>{};
  final notes = <String, Note>{};

  static String habitType(Habit h) => h.isScreenTimeHabit
      ? 'screen_time'
      : (h.isBad ? 'quit' : 'build');

  /// Bengali if the request has any Bengali letters, else English.
  static String replyLanguageFor(String request) =>
      RegExp(r'[ঀ-৿]').hasMatch(request) ? 'Bengali' : 'English';

  String toJson() => jsonEncode({
    'today': DateFormat('yyyy-MM-dd, EEEE').format(now),
    'habits': [
      for (final e in habits.entries)
        {
          'id': e.key,
          'title': e.value.title,
          'type': habitType(e.value),
          if (!e.value.isBad) 'done_today': e.value.isCompletedToday,
          if (e.value.isBad)
            'slipped_today': e.value.isSlippedToday,
        },
    ],
    'open_todos': [
      for (final e in todos.entries) {'id': e.key, 'title': e.value.title},
    ],
    'note_titles': [
      for (final e in notes.entries)
        {
          'id': e.key,
          'title': e.value.title.trim().isEmpty ? '(untitled)' : e.value.title,
        },
    ],
  });
}

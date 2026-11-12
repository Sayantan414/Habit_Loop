import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:habit_loop/core/screen_time.dart';
import 'package:habit_loop/core/services/gemini_client.dart';
import 'package:habit_loop/data/models/habit.dart';
import 'package:habit_loop/data/models/note.dart';
import 'package:habit_loop/data/models/todo.dart';
import 'package:habit_loop/features/assistant/assistant_actions.dart';
import 'package:habit_loop/features/assistant/assistant_controller.dart';
import 'package:habit_loop/features/assistant/assistant_tools.dart';
import 'package:habit_loop/features/assistant/assistant_report.dart';

/// A habit whose day 1 was [daysAgo] days ago.
Habit _habit(
  String id,
  String title, {
  int daysAgo = 2,
  bool isBad = false,
  List<String>? screenApps,
  List<int>? done,
  List<int>? slips,
  bool isPaused = false,
}) => Habit(
  id: id,
  title: title,
  totalDays: 21,
  startDate: DateTime.now().subtract(Duration(days: daysAgo)),
  colorValue: 0,
  isBad: isBad,
  screenTimeLimit: screenApps == null ? null : 30,
  screenTimeApps: screenApps,
  completedDays: done,
  slipDays: slips,
  isPaused: isPaused,
);

/// The app's data in memory, changed only through [AssistantStore].
class _FakeStore implements AssistantStore {
  @override
  final habits = <Habit>[];
  @override
  final allTodos = <Todo>[];
  @override
  final notes = <Note>[];
  final settings = <AssistantSetting, String>{
    AssistantSetting.theme: 'system',
    AssistantSetting.sound: 'on',
    AssistantSetting.vibration: 'on',
  };
  var usage = <String, Map<String, int>>{};
  int? usageDaysAsked;
  var _next = 0;

  @override
  bool get hasScreenTime => true;

  @override
  List<Todo> get todos => allTodos.where((t) => !t.isCompleted).toList();

  @override
  Future<void> setHabitDays(
    Habit habit, {
    required List<int> completedDays,
    required List<int> slipDays,
  }) async {
    habit
      ..completedDays = completedDays
      ..slipDays = slipDays;
  }

  @override
  Future<Habit> addHabit(HabitDraft draft) async {
    final habit =
        _habit('new${_next++}', draft.title, daysAgo: 0, isBad: draft.isBad)
          ..totalDays = draft.days
          ..reminderTimes = draft.reminderTimes;
    habits.add(habit);
    return habit;
  }

  @override
  Future<void> deleteHabit(String id) async =>
      habits.removeWhere((h) => h.id == id);

  @override
  Future<Todo> addTodo(String title) async {
    final todo = Todo(id: 'todo${_next++}', title: title);
    allTodos.add(todo);
    return todo;
  }

  @override
  Future<void> toggleTodo(Todo todo) async =>
      todo.isCompleted = !todo.isCompleted;

  @override
  Future<void> deleteTodo(String id) async =>
      allTodos.removeWhere((t) => t.id == id);

  @override
  Future<void> restoreTodo(Todo todo) async => allTodos.add(todo);

  @override
  Future<Note> addNote(String title, String content) async {
    final note = Note(id: 'note${_next++}', title: title, content: content);
    notes.add(note);
    return note;
  }

  @override
  Future<void> deleteNote(String id) async =>
      notes.removeWhere((n) => n.id == id);

  @override
  Future<void> restoreNote(Note note) async => notes.add(note);

  @override
  String settingValue(AssistantSetting setting) => settings[setting]!;

  @override
  Future<void> setSetting(AssistantSetting setting, String value) async =>
      settings[setting] = value;

  @override
  Future<Map<String, Map<String, int>>> screenTimeUsage({
    required int days,
  }) async {
    usageDaysAsked = days;
    return usage;
  }

  @override
  Future<Map<String, String>> appLabels() async => const {};
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  // No charset, as Google sends it.
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _call(
  String name, [
  Map<String, dynamic> args = const {},
]) => {
  'type': 'function_call',
  'id': 'c-$name',
  'name': name,
  'arguments': args,
};

Map<String, dynamic> _text(String text) => {
  'type': 'model_output',
  'content': [
    {'type': 'text', 'text': text},
  ],
};

/// Gemini answering every interaction with [steps]; keeps what was sent.
class _FakeGemini {
  _FakeGemini(this.steps);

  List<Map<String, dynamic>> Function(Map<String, dynamic> body) steps;
  final bodies = <Map<String, dynamic>>[];
  http.Response? Function(String model)? fail;

  late final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    bodies.add(body);
    final failure = fail?.call(body['model'] as String);
    if (failure != null) return failure;
    return _json({
      'id': 'interactions/i1',
      'status': 'completed',
      'steps': steps(body),
    });
  });
}

void main() {
  group('GeminiClient.interact', () {
    test('sends tools statelessly and reads calls and text', () async {
      final gemini = _FakeGemini(
        (_) => [
          _text('ঠিক আছে'),
          _call('add_todos', {
            'titles': ['wash car'],
          }),
        ],
      );
      final reply = await GeminiClient(apiKey: 'k', client: gemini.client)
          .interact(
            systemInstruction: 'rules',
            input: 'hello',
            tools: AssistantTools.declarations([AssistantTools.addTodos]),
          );

      expect(reply.text, 'ঠিক আছে');
      expect(reply.calls.single.name, 'add_todos');
      expect(reply.calls.single.args['titles'], ['wash car']);
      final body = gemini.bodies.single;
      expect(body['model'], GeminiClient.chatModels.first);
      expect(body['store'], false);
      expect(body['system_instruction'], 'rules');
      expect((body['tools'] as List).single['name'], 'add_todos');
    });

    test('moves to the next model when one is rate limited or gone', () async {
      final gemini = _FakeGemini((_) => [_text('ok')])
        ..fail = (model) => model == GeminiClient.chatModels.first
            ? http.Response('', 429)
            : null;
      final reply = await GeminiClient(
        apiKey: 'k',
        client: gemini.client,
      ).interact(systemInstruction: '', input: 'x');

      expect(reply.text, 'ok');
      expect(
        gemini.bodies.map((b) => b['model']),
        GeminiClient.chatModels.take(2),
      );
      expect(reply.model, GeminiClient.chatModels[1]);

      gemini.fail = (_) => http.Response('', 404);
      expect(
        () => GeminiClient(
          apiKey: 'k',
          client: gemini.client,
        ).interact(systemInstruction: '', input: 'x'),
        throwsA(
          isA<GeminiException>().having((e) => e.code, 'code', 'gemini_server'),
        ),
      );
    });

    test('an overloaded model hands over to the next', () async {
      const busy =
          '{"error":{"code":503,"message":"gemini-3.8-flash is currently '
          'experiencing high demand"}}';
      final gemini = _FakeGemini((_) => [_text('ok')])
        ..fail = (model) => model == GeminiClient.chatModels.first
            ? http.Response(busy, 503)
            : null;
      final client = GeminiClient(apiKey: 'k', client: gemini.client);
      expect(
        (await client.interact(systemInstruction: '', input: 'x')).text,
        'ok',
      );

      gemini.fail = (_) => http.Response(busy, 503);
      expect(
        () => client.interact(systemInstruction: '', input: 'x'),
        throwsA(
          isA<GeminiException>()
              .having((e) => e.code, 'code', 'gemini_busy')
              .having((e) => e.detail, 'detail', contains('high demand')),
        ),
      );
    });

    test('a model too slow to answer is skipped', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: 'k',
        chatTimeout: const Duration(milliseconds: 50),
        client: MockClient((request) async {
          if (calls++ == 0) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          return _json({
            'steps': [_text('quick one')],
          });
        }),
      );
      final reply = await client.interact(systemInstruction: '', input: 'x');
      expect(reply.text, 'quick one');
      expect(calls, 2);
    });

    test('asks for light thinking, and drops it if a model refuses', () async {
      final gemini = _FakeGemini((_) => [_text('ok')])..fail = (_) => null;
      gemini.fail = (model) =>
          gemini.bodies.last['generation_config']['thinking_level'] != null
          ? http.Response(
              '{"error":{"message":"thinking_level is not supported"}}',
              400,
            )
          : null;
      final reply = await GeminiClient(
        apiKey: 'k',
        client: gemini.client,
      ).interact(systemInstruction: '', input: 'x');

      expect(reply.text, 'ok');
      expect(gemini.bodies.first['generation_config']['thinking_level'], 'low');
      expect(
        gemini.bodies.last['generation_config'],
        isNot(contains('thinking_level')),
      );
      expect(gemini.bodies.map((b) => b['model']).toSet(), {
        GeminiClient.chatModels.first,
      });
    });
  });

  group('AssistantContext', () {
    test('sends running habits, open to-dos and note titles under aliases', () {
      final context = AssistantContext(
        habits: [
          _habit('a', 'Walk', done: [3]),
          _habit('b', 'Paused', isPaused: true),
          _habit(
            'c',
            'Instagram under 30 min',
            isBad: true,
            screenApps: ['com.instagram.android'],
          ),
        ],
        todos: [
          Todo(id: 't-open', title: 'Cook'),
          Todo(id: 't-done', title: 'Old', isCompleted: true),
        ],
        notes: [Note(id: 'n-1', title: 'Trip', content: 'secret plans')],
      );
      final json = jsonDecode(context.toJson()) as Map<String, dynamic>;

      expect(json['habits'], [
        {'id': 'h1', 'title': 'Walk', 'type': 'build', 'done_today': true},
        {
          'id': 'h2',
          'title': 'Instagram under 30 min',
          'type': 'screen_time',
          'slipped_today': false,
        },
      ]);
      expect(json['open_todos'], [
        {'id': 't1', 'title': 'Cook'},
      ]);
      expect(json['note_titles'], [
        {'id': 'n1', 'title': 'Trip'},
      ]);
      expect(context.toJson(), isNot(contains('secret plans')));
      expect(context.toJson(), isNot(contains('t-open')));
    });

    test('replies in Bengali when the request has Bengali in it', () {
      expect(AssistantContext.replyLanguageFor('আজকে walk done'), 'Bengali');
      expect(AssistantContext.replyLanguageFor('add a todo'), 'English');
    });
  });

  group('AssistantActions.parse', () {
    final context = AssistantContext(
      habits: [
        _habit('a', 'Walk'),
        _habit('b', 'No sugar', isBad: true),
        _habit(
          'c',
          'Instagram under 30 min',
          isBad: true,
          screenApps: ['com.instagram.android'],
        ),
      ],
      todos: [Todo(id: 'x', title: 'Cook')],
      notes: const [],
    );
    ParsedCall parse(String name, [Map<String, dynamic> args = const {}]) =>
        AssistantActions.parse(GeminiCall(name, args), context);

    test('refuses ids it never sent and the wrong kind of habit', () {
      expect(parse('complete_habit', {'habit_id': 'h9'}).problem, isNotNull);
      expect(
        parse('complete_habit', {'habit_id': 'h2'}).problem,
        contains('quitting'),
      );
      expect(
        parse('log_slip', {'habit_id': 'h3'}).problem,
        contains('screen time'),
      );
      expect(parse('log_slip', {'habit_id': 'h1'}).problem, isNotNull);
      expect(
        parse('log_slip', {'habit_id': 'h2'}).action,
        isA<LogSlipAction>(),
      );
      expect(parse('delete_habit', {'habit_id': 'h1'}).problem, isNotNull);
    });

    test('only the tools allowed for the request', () {
      final parsed = AssistantActions.parse(
        const GeminiCall('delete_todo', {'todo_id': 't1'}),
        context,
        allowed: const [AssistantTools.addTodos],
      );
      expect(parsed.action, isNull);
    });

    test('a new habit runs 21 days unless told otherwise', () {
      final plain = parse('add_habit', {
        'title': 'Read',
        'kind': 'build',
      }).action;
      expect((plain! as AddHabitAction).draft.days, 21);
      expect(plain.needsConfirmation, isTrue);

      final quit =
          parse('add_habit', {
                'title': 'No soda',
                'kind': 'quit',
                'days': 30,
                'reminder_times': ['21:30', '7:05', 'later'],
              }).action!
              as AddHabitAction;
      expect(quit.draft.isBad, isTrue);
      expect(quit.draft.days, 30);
      // Quit habits have no reminders.
      expect(quit.draft.reminderTimes, isEmpty);

      final build =
          parse('add_habit', {
                'title': 'Walk',
                'kind': 'build',
                'reminder_times': ['21:30', '7:05', 'later'],
              }).action!
              as AddHabitAction;
      expect(build.draft.reminderTimes, [425, 1290]);
    });

    test('settings take only values the app knows', () {
      final dark = parse('change_setting', {
        'setting': 'theme',
        'value': 'Dark',
      }).action;
      expect((dark! as ChangeSettingAction).value, 'dark');
      expect(
        parse('change_setting', {'setting': 'theme', 'value': 'pink'}).problem,
        isNotNull,
      );
      // The doomscroll reminder went away with the reels counter.
      expect(
        parse('change_setting', {
          'setting': 'doomscroll_reminder',
          'value': 'off',
        }).problem,
        isNotNull,
      );
      expect(
        parse('change_setting', {'setting': 'wifi', 'value': 'on'}).problem,
        isNotNull,
      );
    });
  });

  group('AssistantController', () {
    late _FakeStore store;
    late _FakeGemini gemini;
    late AssistantController assistant;

    setUp(() {
      store = _FakeStore();
      gemini = _FakeGemini((_) => const []);
      assistant = AssistantController(
        store: store,
        client: () => GeminiClient(apiKey: 'k', client: gemini.client),
      );
    });

    test('several to-dos at once, taken back with one Undo', () async {
      gemini.steps = (_) => [
        _call('add_todos', {
          'titles': ['wash car', 'exercise', 'read', 'cook'],
        }),
      ];
      await assistant.send('four to-dos: wash car, exercise, read, cook');

      expect(store.todos.map((t) => t.title), [
        'wash car',
        'exercise',
        'read',
        'cook',
      ]);
      final turn = assistant.state.single;
      expect(turn.items.single.outcome!.title, 'Added 4 to-dos');
      expect(turn.model, GeminiClient.chatModels.first);
      expect(turn.elapsed, isNotNull);
      expect(turn.canUndo, isTrue);

      await assistant.undo(turn);
      expect(store.todos, isEmpty);
      expect(turn.undone, isTrue);
      expect(turn.canUndo, isFalse);
    });

    test('runs a mixed request and undoes all of it', () async {
      store.habits.add(_habit('a', 'Walk'));
      gemini.steps = (_) => [
        _call('complete_habit', {'habit_id': 'h1'}),
        _call('add_note', {'title': 'Trip', 'content': '- hotel\n- train'}),
        _call('change_setting', {'setting': 'theme', 'value': 'dark'}),
      ];
      await assistant.send('walk done, trip note, dark mode');

      expect(store.habits.single.isCompletedToday, isTrue);
      expect(store.notes.single.content, '- hotel\n- train');
      expect(store.settings[AssistantSetting.theme], 'dark');

      await assistant.undo(assistant.state.single);
      expect(store.habits.single.isCompletedToday, isFalse);
      expect(store.notes, isEmpty);
      expect(store.settings[AssistantSetting.theme], 'system');
    });

    test('never un-checks a habit that was already done', () async {
      final walk = _habit('a', 'Walk', daysAgo: 2, done: [3]);
      store.habits.add(walk);
      gemini.steps = (_) => [
        _call('complete_habit', {'habit_id': 'h1'}),
      ];
      await assistant.send('walk done');

      expect(walk.completedDays, [3]);
      expect(
        assistant.state.single.items.single.outcome!.kind,
        OutcomeKind.info,
      );
      expect(assistant.state.single.canUndo, isFalse);
    });

    test('deletes wait for the OK, and cancel leaves things alone', () async {
      store.allTodos.addAll([
        Todo(id: 'x', title: 'Cook'),
        Todo(id: 'y', title: 'Run'),
      ]);
      gemini.steps = (_) => [
        _call('delete_todo', {'todo_id': 't1'}),
        _call('delete_todo', {'todo_id': 't2'}),
      ];
      await assistant.send('delete both');

      final turn = assistant.state.single;
      expect(store.todos, hasLength(2));
      expect(turn.items.every((i) => i.waiting), isTrue);

      assistant.cancel(turn.items[1]);
      await assistant.confirm(turn, turn.items[0]);
      expect(store.todos.map((t) => t.title), ['Run']);

      await assistant.undo(turn);
      expect(store.todos.map((t) => t.title).toSet(), {'Cook', 'Run'});
    });

    test('a new habit is only created after Create', () async {
      gemini.steps = (_) => [
        _call('add_habit', {'title': 'Read 20 min', 'kind': 'build'}),
      ];
      await assistant.send('habit to read 20 minutes');
      expect(store.habits, isEmpty);

      final turn = assistant.state.single;
      await assistant.confirm(turn, turn.items.single);
      expect(store.habits.single.title, 'Read 20 min');
      expect(store.habits.single.totalDays, 21);

      await assistant.undo(turn);
      expect(store.habits, isEmpty);
    });

    test('a note is shared only on Share, and then with no tools', () async {
      store.notes.add(Note(id: 'n', title: 'Shopping', content: 'milk, eggs'));
      gemini.steps = (body) => body.containsKey('tools')
          ? [
              _call('read_note', {'note_id': 'n1'}),
            ]
          : [_text('Milk and eggs.')];
      await assistant.send("what's on my shopping list?");

      final turn = assistant.state.single;
      expect(gemini.bodies.single['input'], isNot(contains('milk')));

      await assistant.showNoteOnly(turn, turn.items.single);
      expect(turn.items.single.outcome!.detail, 'milk, eggs');
      expect(gemini.bodies, hasLength(1));

      await assistant.send('and the shopping note again?');
      final second = assistant.state.last;
      await assistant.confirm(second, second.items.single);
      expect(second.items.single.answer, 'Milk and eggs.');
      final shared = gemini.bodies.last;
      expect(shared['input'], contains('milk, eggs'));
      expect(shared.containsKey('tools'), isFalse);
    });

    test('a report for the days asked, with nothing to undo', () async {
      store.allTodos.add(Todo(id: 'x', title: 'Cook'));
      gemini.steps = (_) => [
        _call('report', {
          'topics': ['todos', 'screen_time'],
          'days': 14,
        }),
      ];
      await assistant.send('report for the last 2 weeks');

      final outcome = assistant.state.single.items.single.outcome!;
      expect(outcome.title, 'Your last 2 weeks');
      expect(outcome.report!.days, 14);
      expect(outcome.report!.todos!.open, 1);
      expect(outcome.report!.habits, isNull);
      // Two weeks and the two before, cut to the week Android keeps.
      expect(store.usageDaysAsked, 7);
      expect(assistant.state.single.canUndo, isFalse);
    });

    test('earlier requests go along as history', () async {
      gemini.steps = (_) => [
        _call('add_todos', {
          'titles': ['read'],
        }),
      ];
      await assistant.send('add read');
      await assistant.send('and one more: cook');

      final input = gemini.bodies.last['input'] as String;
      expect(input, contains('User: add read'));
      expect(input, contains('done: Added a to-do'));
      expect(input, contains('Request: and one more: cook'));
    });

    test(
      'explains a missing key or no internet without touching data',
      () async {
        final noKey = AssistantController(store: store, client: () => null);
        await noKey.send('add read');
        expect(noKey.state.single.error, contains('Settings'));

        gemini.fail = (_) => throw http.ClientException('offline');
        await assistant.send('add read');
        expect(assistant.state.single.error, contains('internet'));
        expect(store.todos, isEmpty);
      },
    );
  });

  group('AssistantReport', () {
    final now = DateTime(2026, 10, 24, 20);
    // Day 1 was Oct 15, so Oct 18-24 is days 4 to 10.
    final start = DateTime(2026, 10, 15);
    final walk = Habit(
      id: 'w',
      title: 'Walk',
      totalDays: 21,
      startDate: start,
      colorValue: 0,
      completedDays: [1, 4, 5, 9, 10],
    );
    final sugar = Habit(
      id: 's',
      title: 'No sugar',
      totalDays: 21,
      startDate: start,
      colorValue: 0,
      isBad: true,
      slipDays: [6],
    );
    const insta = 'com.instagram.android';
    const yt = 'com.google.android.youtube';
    final phone = Habit(
      id: 'p',
      title: 'Instagram + YouTube under 30 min',
      totalDays: 21,
      startDate: start,
      colorValue: 0,
      isBad: true,
      screenTimeLimit: 30,
      screenTimeApps: [insta, yt],
    );
    final usage = {
      usageDayKey(DateTime(2026, 10, 24)): {insta: 12, yt: 2, 'com.other': 50},
      usageDayKey(DateTime(2026, 10, 21)): {insta: 40},
      usageDayKey(DateTime(2026, 10, 18)): {insta: 3},
    };

    test('a week of habits and screen time on the tracked apps', () {
      final report = AssistantReport.compute(
        days: 7,
        topics: ReportTopic.values.toSet(),
        habits: [walk, sugar, phone],
        screenTimeUsage: usage,
        appLabels: const {insta: 'Instagram'},
        hasScreenTime: true,
        now: now,
      );

      final w = report.habits!.firstWhere((h) => h.title == 'Walk');
      expect(w.done, 4);
      expect(w.days, 7);
      final s = report.habits!.firstWhere((h) => h.title == 'No sugar');
      expect(s.slips, 1);
      expect(s.done, 5); // six finished days, one slip; today isn't over
      expect(report.from, DateTime(2026, 10, 18));
      final screen = report.screenTime!;
      // Apps no habit tracks ('com.other') are left out.
      expect(screen.byDay, [3, 0, 0, 40, 0, 0, 14]);
      expect(screen.total, 57);
      expect(screen.byApp, {insta: 55, yt: 2});
      expect(screen.busiestDay, 3);
      expect(screen.labels[insta], 'Instagram');
      // The week before is older than Android's history.
      expect(screen.previousTotal, isNull);
    });

    test('a short report compares with the days just before', () {
      final report = AssistantReport.compute(
        days: 3,
        topics: {ReportTopic.screenTime},
        habits: [phone],
        screenTimeUsage: usage,
        hasScreenTime: true,
        now: now,
      );
      expect(report.screenTime!.byDay, [0, 0, 14]);
      expect(report.screenTime!.previousTotal, 40);
    });

    test('says so when no habit tracks screen time', () {
      final report = AssistantReport.compute(
        days: 7,
        topics: {ReportTopic.screenTime},
        habits: [walk],
        screenTimeUsage: usage,
        hasScreenTime: true,
        now: now,
      );
      expect(report.screenTime!.trackedApps, 0);
      expect(report.screenTime!.total, 0);
    });

    test('any number of days the user asks for', () {
      final report = AssistantReport.compute(
        days: 13,
        topics: {ReportTopic.habits},
        habits: [walk],
        now: now,
      );
      expect(report.from, DateTime(2026, 10, 12));
      // Oct 15 (day 1) to Oct 24: ten challenge days fell in the range.
      expect(report.habits!.single.days, 10);
      expect(report.habits!.single.done, 5);
      expect(report.todos, isNull);
      expect(report.screenTime, isNull);
    });

    test('screen time older than the week Android keeps is left out', () {
      final report = AssistantReport.compute(
        days: 30,
        topics: {ReportTopic.screenTime},
        habits: [phone],
        screenTimeUsage: usage,
        hasScreenTime: true,
        now: now,
      );
      expect(report.screenTime!.byDay, hasLength(screenTimeHistoryDays));
      expect(report.screenTime!.previousTotal, isNull);
      expect(AssistantReport.screenTimeDaysNeeded(2), 4);
      expect(AssistantReport.screenTimeDaysNeeded(14), screenTimeHistoryDays);
    });

    test('to-dos left, done, and the oldest one waiting', () {
      final report = AssistantReport.compute(
        days: 7,
        topics: {ReportTopic.todos},
        todos: [
          Todo(id: '1', title: 'Old task', createdAt: DateTime(2026, 10, 1)),
          Todo(id: '2', title: 'New task', createdAt: DateTime(2026, 10, 23)),
          Todo(
            id: '3',
            title: 'Done',
            isCompleted: true,
            createdAt: DateTime(2026, 10, 20),
          ),
        ],
        now: now,
      );
      final todos = report.todos!;
      expect(todos.open, 2);
      expect(todos.done, 1);
      expect(todos.addedInPeriod, 2);
      expect(todos.oldestOpen, 'Old task');
      expect(todos.oldestOpenDays, 23);
    });

    test('the model picks the days; a week if it does not say', () {
      final context = AssistantContext(habits: [], todos: [], notes: []);
      final twoWeeks =
          AssistantActions.parse(
                const GeminiCall('report', {
                  'topics': ['screen_time'],
                  'days': 14,
                }),
                context,
              ).action!
              as ReportAction;
      expect(twoWeeks.days, 14);
      expect(twoWeeks.topics, {ReportTopic.screenTime});

      final plain =
          AssistantActions.parse(
                const GeminiCall('report', {}),
                context,
              ).action!
              as ReportAction;
      expect(plain.days, 7);
      expect(plain.topics, ReportTopic.values.toSet());

      expect(AssistantActions.reportTitle(1), 'Today');
      expect(AssistantActions.reportTitle(13), 'Your last 13 days');
      expect(AssistantActions.reportTitle(28), 'Your last 4 weeks');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:habit_loop/core/services/gemini_speech_engine.dart';
import 'package:habit_loop/core/services/gemini_transcriber.dart';
import 'package:habit_loop/core/services/speech_service.dart';

const _channel = MethodChannel('habitloop/speech');
const _uploadUrl = 'https://upload.test/session-1';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      // No charset, as Google sends it.
      headers: {'content-type': 'application/json'},
    );

http.Response _transcript(String text) => _json({
      'id': 'interactions/i1',
      'status': 'completed',
      'steps': [
        {
          'type': 'model_output',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      ],
    });

/// The Gemini API as the transcriber uses it: Files API upload, the
/// interaction, and the clean-up delete. [interaction] answers the
/// transcription call, numbered from 1.
class _FakeGemini {
  _FakeGemini(this.interaction, {this.poll});

  http.Response Function(int call) interaction;

  /// Answers checks on a running interaction, numbered from 1.
  final http.Response Function(int call)? poll;
  int polls = 0;
  final requests = <http.Request>[];
  int interactionCalls = 0;
  int deletes = 0;

  late final client = MockClient((request) async {
    requests.add(request);
    final url = request.url.toString();
    if (url.endsWith('/upload/v1beta/files')) {
      return http.Response('', 200, headers: {'x-goog-upload-url': _uploadUrl});
    }
    if (url == _uploadUrl) {
      return _json({
        'file': {'uri': 'https://files.test/f1', 'name': 'files/f1'},
      });
    }
    if (url.endsWith('/v1beta/interactions')) {
      return interaction(++interactionCalls);
    }
    if (request.method == 'GET' && url.endsWith('/v1beta/interactions/i1')) {
      return poll!(++polls);
    }
    if (request.method == 'DELETE' && url.endsWith('/v1beta/files/f1')) {
      deletes++;
      return http.Response('{}', 200);
    }
    if (url.endsWith('/v1beta/models')) return _json({'models': []});
    return http.Response('unexpected $url', 404);
  });

  /// The JSON sent to the transcription endpoint.
  Map<String, dynamic> get lastInteractionBody => jsonDecode(
        requests.lastWhere((r) => r.url.path.endsWith('/interactions')).body,
      ) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeminiTranscriber', () {
    test('uploads, transcribes with the languages, then deletes the file',
        () async {
      final gemini = _FakeGemini((_) => _transcript(' আজকে meeting আছে '));
      final transcriber =
          GeminiTranscriber(apiKey: 'AIza-test', client: gemini.client);

      final text = await transcriber.transcribe(
        Uint8List.fromList([1, 2, 3]),
        languages: ['bn-IN', 'en-IN'],
      );
      await Future<void>.delayed(Duration.zero);

      expect(text, 'আজকে meeting আছে');
      final start = gemini.requests.first;
      expect(start.headers['x-goog-api-key'], 'AIza-test');
      expect(start.headers['X-Goog-Upload-Header-Content-Length'], '3');
      expect(gemini.requests[1].bodyBytes, [1, 2, 3]);
      final body = gemini.lastInteractionBody;
      expect(body['model'], 'gemini-3.5-transcribe');
      expect(body['input'][0]['uri'], 'https://files.test/f1');
      expect(
        body['generation_config']['transcription_config']['language_codes'],
        ['bn-IN', 'en-IN'],
      );
      expect(gemini.deletes, 1);
    });

    test('waits for a transcription that is still running', () async {
      final running = _json({'id': 'interactions/i1', 'status': 'in_progress'});
      final gemini = _FakeGemini(
        (_) => running,
        poll: (n) => n < 2 ? running : _transcript('done at last'),
      );
      final transcriber = GeminiTranscriber(apiKey: 'k', client: gemini.client);

      expect(await transcriber.transcribe(Uint8List(1)), 'done at last');
      expect(gemini.polls, 2);
    });

    test('reads output_text when the response has it', () {
      expect(
        GeminiTranscriber.transcriptOf({'output_text': ' hello '}),
        'hello',
      );
    });

    test('maps a bad key, a rate limit and a dropped connection', () async {
      Future<String?> codeFor(http.Response Function() response) async {
        final gemini = _FakeGemini((_) => response());
        try {
          await GeminiTranscriber(apiKey: 'k', client: gemini.client)
              .transcribe(Uint8List(1));
          return null;
        } on TranscriptionException catch (e) {
          return e.code;
        }
      }

      expect(
        await codeFor(() => http.Response('{"reason":"API_KEY_INVALID"}', 400)),
        'gemini_auth',
      );
      expect(await codeFor(() => http.Response('', 429)), 'gemini_quota');
      expect(await codeFor(() => http.Response('', 500)), 'gemini_server');
      expect(
        await codeFor(() => throw http.ClientException('offline')),
        'gemini_network',
      );
    });
  });

  group('GeminiSpeechEngine', () {
    late Directory temp;
    late File recording;
    late List<String> calls;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('gemini_test');
      recording = File('${temp.path}/dictation.m4a');
      await recording.writeAsBytes([7, 7, 7]);
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'ensureMicPermission':
            return true;
          case 'startMemo':
            return 'ok';
          case 'stopMemo':
            return (call.arguments as Map)['keep'] == true
                ? recording.path
                : null;
        }
        return null;
      });
    });

    tearDown(() => temp.delete(recursive: true));

    Future<(GeminiSpeechEngine, List<String>, List<String>)> start(
      _FakeGemini gemini, {
      String locale = 'bn-IN',
    }) async {
      final engine = GeminiSpeechEngine(
        GeminiTranscriber(apiKey: 'k', client: gemini.client),
      );
      final words = <String>[];
      final errors = <String>[];
      engine
        ..onWords = ((w, _) => words.add(w))
        ..onError = errors.add;
      expect((await engine.prepare(locale)).available, isTrue);
      await engine.listen(localeId: locale);
      return (engine, words, errors);
    }

    test('stopping transcribes the whole take and deletes the recording',
        () async {
      final gemini = _FakeGemini((_) => _transcript('পুরো নোটটা এখানে'));
      final (engine, words, errors) = await start(gemini);

      await engine.stop();

      expect(words, ['পুরো নোটটা এখানে']);
      expect(errors, isEmpty);
      expect(recording.existsSync(), isFalse);
      expect(
        gemini.lastInteractionBody['generation_config']
            ['transcription_config']['language_codes'],
        ['bn-IN', 'en-IN'],
      );
    });

    test('English asks for English only', () async {
      final gemini = _FakeGemini((_) => _transcript('buy milk'));
      final (engine, _, _) = await start(gemini, locale: 'en-IN');

      await engine.stop();

      expect(
        gemini.lastInteractionBody['generation_config']
            ['transcription_config']['language_codes'],
        ['en-IN'],
      );
    });

    test('retries a rate limit without bothering the user', () async {
      final gemini = _FakeGemini(
        (n) => n == 1
            ? http.Response('', 429, headers: {'retry-after': '0'})
            : _transcript('second time lucky'),
      );
      final (engine, words, errors) = await start(gemini);

      await engine.stop();

      expect(words, ['second time lucky']);
      expect(errors, isEmpty);
    });

    test('a failed take is kept so it can be retried', () async {
      var keyFixed = false;
      final gemini = _FakeGemini(
        (_) => keyFixed
            ? _transcript('saved after all')
            : http.Response('{"reason":"API_KEY_INVALID"}', 400),
      );
      final (engine, words, errors) = await start(gemini);

      await engine.stop();
      expect(errors, ['gemini_auth']);
      expect(words, isEmpty);
      expect(engine.canRetry, isTrue);
      // The file is gone either way; the audio lives on in memory.
      expect(recording.existsSync(), isFalse);

      keyFixed = true;
      expect(await engine.retryFailed(), 'saved after all');
      expect(engine.canRetry, isFalse);
    });

    test('cancelling throws the recording away unsent', () async {
      final gemini = _FakeGemini((_) => _transcript('never sent'));
      final (engine, words, _) = await start(gemini);

      await engine.cancel();

      expect(words, isEmpty);
      expect(gemini.requests, isEmpty);
      expect(calls, contains('stopMemo'));
    });

    test('hitting the length limit ends the take', () async {
      final gemini = _FakeGemini((_) => _transcript('x'));
      final (engine, _, _) = await start(gemini);
      final ends = <bool>[];
      engine.onSessionEnd = ends.add;

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onMemoLimit')),
        (_) {},
      );

      expect(ends, [true]);
    });
  });

  group('DictationController with Gemini', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('gemini_test');
      final recording = File('${temp.path}/dictation.m4a');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'ensureMicPermission':
            return true;
          case 'startMemo':
            await recording.writeAsBytes([1]);
            return 'ok';
          case 'stopMemo':
            return recording.path;
        }
        return null;
      });
    });

    tearDown(() => temp.delete(recursive: true));

    test('shows Transcribing while waiting, then keeps the text', () async {
      final gemini = _FakeGemini((_) => _transcript('the whole note'));
      final dictation = DictationController(
        GeminiSpeechEngine(GeminiTranscriber(apiKey: 'k', client: gemini.client)),
      );
      await dictation.start(localeId: 'en-IN');

      final stopping = dictation.stop();
      expect(dictation.isFinishing, isTrue);
      await stopping;

      expect(dictation.isListening, isFalse);
      expect(dictation.text, 'the whole note');
      dictation.dispose();
    });

    test('a failure offers retry, and the retried text is recovered',
        () async {
      var online = false;
      final gemini = _FakeGemini(
        (_) => online ? _transcript('recovered note') : http.Response('', 401),
      );
      String? problem;
      String? recovered;
      final dictation = DictationController(
        GeminiSpeechEngine(GeminiTranscriber(apiKey: 'k', client: gemini.client)),
      )
        ..onProblem = ((m) => problem = m)
        ..onRecovered = ((t) => recovered = t);
      await dictation.start(localeId: 'en-IN');

      await dictation.stop();
      expect(problem, contains('Gemini key'));
      expect(dictation.canRetry, isTrue);

      online = true;
      await dictation.retryFailed();
      expect(recovered, 'recovered note');
      dictation.dispose();
    });
  });
}

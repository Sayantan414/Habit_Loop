import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_loop/core/services/speech_service.dart';

/// Stands in for Android's recognizer: the test plays the recognizer's
/// callbacks by hand.
class _FakeEngine extends SpeechEngine {
  _FakeEngine({this.setup = const SpeechSetup(available: true)});

  final SpeechSetup setup;
  final listens = <String>[];
  final downloads = <String>[];
  final quiet = <bool>[];
  int stops = 0;

  @override
  Future<void> setQuiet(bool value) async => quiet.add(value);

  @override
  Future<SpeechSetup> prepare(String localeId) async => setup;

  @override
  Future<bool> downloadLanguage(String localeId) async {
    downloads.add(localeId);
    return true;
  }

  @override
  Future<String> describe() async => 'fake';

  @override
  Future<void> listen({required String localeId}) async => listens.add(localeId);

  @override
  Future<void> stop() async => stops++;

  void say(String words, {bool isFinal = false}) => onWords?.call(words, isFinal);
  void end({bool idle = false}) => onSessionEnd?.call(idle);
  void fail(String code) => onError?.call(code);
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('DictationController', () {
    late _FakeEngine engine;
    late DictationController dictation;

    setUp(() {
      engine = _FakeEngine();
      dictation = DictationController(engine, restartDelay: Duration.zero);
    });

    tearDown(() => dictation.dispose());

    test('keeps listening across Android pause timeouts', () async {
      await dictation.start(localeId: 'bn-IN');
      engine.say('আজ বাজার');
      engine.say('আজ বাজার যেতে হবে', isFinal: true);
      engine.end();
      await _tick();

      expect(engine.listens, ['bn-IN', 'bn-IN']);
      engine.say('buy milk');
      expect(dictation.text, 'আজ বাজার যেতে হবে buy milk');
      expect(dictation.isListening, isTrue);
    });

    test('silences beeps for the whole take, not per session', () async {
      await dictation.start(localeId: 'en-IN');
      engine.say('one', isFinal: true);
      engine.end();
      await _tick();
      engine.say('two', isFinal: true);
      engine.end();
      await _tick();
      expect(engine.quiet, [true]);
      await dictation.stop();
      expect(engine.quiet, [true, false]);
    });

    test('a failed start never mutes', () async {
      final denied = _FakeEngine(
        setup: const SpeechSetup(available: false, problem: 'permission'),
      );
      final controller = DictationController(denied);
      await controller.start(localeId: 'en-IN');
      expect(denied.quiet, isEmpty);
      controller.dispose();
    });

    test('partial words survive a session that ends without a final', () async {
      await dictation.start(localeId: 'en-IN');
      engine.say('call the');
      engine.end();
      await _tick();
      engine.say('plumber');
      expect(dictation.text, 'call the plumber');
    });

    test('ignores a repeated final result', () async {
      await dictation.start(localeId: 'en-IN');
      engine.say('read ten pages', isFinal: true);
      engine.say('read ten pages', isFinal: true);
      expect(dictation.text, 'read ten pages');
    });

    test('pause errors restart, but a session end after one does not double up',
        () async {
      await dictation.start(localeId: 'en-IN');
      engine.say('hello');
      engine.fail('error_no_match');
      engine.end();
      await _tick();
      expect(engine.listens.length, 2);
      expect(dictation.isListening, isTrue);
    });

    test('a dropped connection on a pause restarts quietly', () async {
      String? problem;
      dictation.onProblem = (m) => problem = m;
      await dictation.start(localeId: 'bn-IN');
      engine.say('আজকে আমি');
      engine.fail('error_server_disconnected');
      await _tick();
      expect(problem, isNull);
      expect(dictation.isListening, isTrue);
      expect(engine.listens.length, 2);
      engine.say('বই পড়েছি', isFinal: true);
      expect(dictation.text, 'আজকে আমি বই পড়েছি');
    });

    test('dropped connections during a long pause stop quietly', () async {
      String? problem;
      dictation.onProblem = (m) => problem = m;
      await dictation.start(localeId: 'en-IN');
      engine.say('putting oil on the machine', isFinal: true);
      engine.end();
      await _tick();
      for (var i = 0; i < dictation.maxSilentSessions; i++) {
        engine.fail('error_server_disconnected');
        await _tick();
      }
      expect(dictation.isListening, isFalse);
      expect(problem, isNull);
      expect(dictation.text, 'putting oil on the machine');
    });

    test('keeps failing with no words heard: gives up and explains', () async {
      String? problem;
      dictation.onProblem = (m) => problem = m;
      await dictation.start(localeId: 'en-IN');
      for (var i = 0; i < dictation.maxFailedSessions; i++) {
        engine.fail('error_network');
        await _tick();
      }
      expect(dictation.isListening, isFalse);
      expect(problem, contains('internet'));
    });

    test('stops by itself after a stretch of silence', () async {
      await dictation.start(localeId: 'en-IN');
      for (var i = 0; i < dictation.maxSilentSessions; i++) {
        engine.end();
        await _tick();
      }
      expect(dictation.isListening, isFalse);
      expect(engine.stops, 1);
    });

    test('a hard error stops and explains', () async {
      String? problem;
      dictation.onProblem = (m) => problem = m;
      await dictation.start(localeId: 'bn-IN');
      engine.fail('error_language_unavailable');
      await _tick();
      expect(dictation.isListening, isFalse);
      expect(problem, contains('language'));
    });

    test('explains a denied microphone', () async {
      final denied = DictationController(_FakeEngine(
        setup: const SpeechSetup(available: false, problem: 'permission'),
      ));
      String? problem;
      denied.onProblem = (m) => problem = m;
      await denied.start(localeId: 'en-IN');
      expect(denied.isListening, isFalse);
      expect(problem, contains('microphone'));
      denied.dispose();
    });

    test('text deleted after a take does not come back on the next one',
        () async {
      await dictation.start(localeId: 'en-IN');
      engine.say('first try', isFinal: true);
      await dictation.stop();
      // The user deletes "first try" from the note, then taps the mic again.
      await dictation.start(localeId: 'en-IN');
      expect(dictation.text, isEmpty);
      engine.say('second try');
      expect(dictation.text, 'second try');
    });

    test('a continuous session keeps going after each segment', () async {
      await dictation.start(localeId: 'bn-IN');
      engine.say('প্রথম লাইন', isFinal: true);
      engine.say('second');
      engine.say('second line', isFinal: true);
      expect(engine.listens.length, 1);
      expect(dictation.text, 'প্রথম লাইন second line');
    });

    test('an idle end of a continuous session stops instead of restarting',
        () async {
      await dictation.start(localeId: 'bn-IN');
      engine.say('done', isFinal: true);
      engine.end(idle: true);
      await _tick();
      expect(dictation.isListening, isFalse);
      expect(engine.listens.length, 1);
    });

    test('offers an offline download once per language', () async {
      final downloadable = _FakeEngine(
        setup: const SpeechSetup(available: true, canDownload: true),
      );
      final offers = <String>[];
      final first = DictationController(downloadable)
        ..onOfferDownload = offers.add;
      await first.start(localeId: 'en-GB');
      await first.stop();
      await first.start(localeId: 'en-GB');
      expect(offers, ['en-GB']);
      await first.downloadLanguage('en-GB');
      expect(downloadable.downloads, ['en-GB']);
      first.dispose();
    });

    test('switching language keeps what was heard', () async {
      await dictation.start(localeId: 'en-IN');
      engine.say('meeting at five');
      await dictation.switchLocale('bn-IN');
      engine.say('মনে রাখতে হবে');
      expect(engine.listens, ['en-IN', 'bn-IN']);
      expect(dictation.text, 'meeting at five মনে রাখতে হবে');
    });
  });

  group('insertDictation', () {
    TextEditingValue at(String text, int offset) => TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: offset),
        );

    test('capitalises into an empty note', () {
      final v = insertDictation(at('', 0), 'buy milk');
      expect(v.text, 'Buy milk');
      expect(v.selection.baseOffset, 8);
    });

    test('spaces itself from the words around the cursor', () {
      final v = insertDictation(at('Buy eggs', 3), 'milk and');
      expect(v.text, 'Buy milk and eggs');
      expect(v.selection.baseOffset, 'Buy milk and'.length);
    });

    test('starts a new sentence after a full stop or a Bengali dari', () {
      expect(insertDictation(at('Done.', 5), 'next').text, 'Done. Next');
      expect(insertDictation(at('কাজ শেষ।', 8), 'আবার').text, 'কাজ শেষ। আবার');
      expect(insertDictation(at('and', 3), 'then').text, 'and then');
    });

    test('replaces a selection, and appends when there is no cursor', () {
      const selected = TextEditingValue(
        text: 'Call Raj today',
        selection: TextSelection(baseOffset: 5, extentOffset: 8),
      );
      expect(insertDictation(selected, 'Mitra').text, 'Call Mitra today');
      expect(
        insertDictation(const TextEditingValue(text: 'Notes'), 'more').text,
        'Notes more',
      );
    });
  });
}

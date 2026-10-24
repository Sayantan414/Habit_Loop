import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Languages offered for dictation. Android recognises one at a time, so
/// mixed Bengali/English speech works best in whichever one dominates.
const dictationLocales = <String, String>{
  'en-IN': 'EN',
  'bn-IN': 'বাং',
};

const defaultDictationLocale = 'en-IN';

/// What the recognizer can do for a language, found before listening.
class SpeechSetup {
  const SpeechSetup({
    required this.available,
    this.continuous = false,
    this.canDownload = false,
    this.problem,
  });

  final bool available;

  /// Listens across pauses on its own (on-device, Android 13+).
  final bool continuous;

  /// The language's offline model can be downloaded for continuous,
  /// offline dictation.
  final bool canDownload;

  /// `permission`, `needs_download` or `unavailable` when not [available].
  final String? problem;
}

/// One recognition backend: [NativeSpeechEngine] (the phone's recognizer)
/// in the app, a fake in tests.
///
/// A "session" is one listen call. Online recognizers end it after every
/// short pause, which [DictationController] papers over.
abstract class SpeechEngine {
  /// Words heard so far in the current stretch of speech (each result
  /// replaces the last), and whether that stretch is finished.
  void Function(String words, bool isFinal)? onWords;

  /// The current session is over. [idle] means the recognizer itself gave
  /// up after a long silence, so dictation should stop, not restart.
  void Function(bool idle)? onSessionEnd;

  /// A recognizer error code such as `error_no_match`.
  void Function(String code)? onError;

  /// Asks for the mic if needed and picks a recognizer for [localeId].
  Future<SpeechSetup> prepare(String localeId);

  Future<void> listen({required String localeId});

  /// Ends the session. Words still on their way are delivered before this
  /// completes.
  Future<void> stop();

  /// Ends the session and drops anything not yet delivered.
  Future<void> cancel() => stop();

  /// Starts the system download of [localeId]'s offline speech model.
  Future<bool> downloadLanguage(String localeId);

  /// Silences the recognizer's start/stop beeps for the length of a take.
  Future<void> setQuiet(bool quiet);

  /// One line on which recognizer is in use, for troubleshooting.
  Future<String> describe();
}

/// The `habitloop/speech` channel (SpeechChannel.kt). Whichever engine is
/// running the current take receives its callbacks.
class SpeechBridge {
  SpeechBridge._() {
    channel.setMethodCallHandler((call) async => _handler?.call(call));
  }

  static final instance = SpeechBridge._();

  final channel = const MethodChannel('habitloop/speech');
  Future<void> Function(MethodCall call)? _handler;

  void claim(Future<void> Function(MethodCall call) handler) =>
      _handler = handler;
}

/// Android's SpeechRecognizer via SpeechChannel.kt.
class NativeSpeechEngine extends SpeechEngine {
  NativeSpeechEngine({SpeechBridge? bridge})
      : _bridge = bridge ?? SpeechBridge.instance;

  final SpeechBridge _bridge;

  MethodChannel get _channel => _bridge.channel;

  Future<void> _onCall(MethodCall call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map);
    switch (call.method) {
      case 'onWords':
        onWords?.call(args['words'] as String, args['final'] as bool);
      case 'onSessionEnd':
        onSessionEnd?.call(args['idle'] as bool);
      case 'onError':
        onError?.call(args['code'] as String);
    }
  }

  @override
  Future<SpeechSetup> prepare(String localeId) async {
    if (!Platform.isAndroid) {
      return const SpeechSetup(available: false, problem: 'unavailable');
    }
    _bridge.claim(_onCall);
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'prepare',
        {'locale': localeId},
      );
      return SpeechSetup(
        available: raw?['available'] as bool? ?? false,
        continuous: raw?['continuous'] as bool? ?? false,
        canDownload: raw?['canDownload'] as bool? ?? false,
        problem: raw?['problem'] as String?,
      );
    } on PlatformException {
      return const SpeechSetup(available: false, problem: 'unavailable');
    }
  }

  @override
  Future<void> listen({required String localeId}) =>
      _channel.invokeMethod<void>('listen', {'locale': localeId});

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing to stop.
    }
  }

  @override
  Future<bool> downloadLanguage(String localeId) async {
    try {
      return await _channel.invokeMethod<bool>(
            'downloadLanguage',
            {'locale': localeId},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> setQuiet(bool quiet) async {
    try {
      await _channel.invokeMethod<void>('setQuiet', {'quiet': quiet});
    } on PlatformException {
      // Beeps stay audible; dictation itself is unaffected.
    }
  }

  @override
  Future<String> describe() async {
    try {
      return await _channel.invokeMethod<String>('describe') ?? '';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }
}

/// Text heard across several sessions: finished sessions plus the one still
/// being recognised.
class DictationTranscript {
  final _committed = <String>[];
  String _partial = '';

  void update(String words) => _partial = words.trim();

  /// Locks in the current session's words, e.g. when it ends.
  void commit() {
    if (_partial.isNotEmpty) _committed.add(_partial);
    _partial = '';
  }

  String get text =>
      [..._committed, if (_partial.isNotEmpty) _partial].join(' ');

  bool get isEmpty => _committed.isEmpty && _partial.isEmpty;

  void clear() {
    _committed.clear();
    _partial = '';
  }
}

/// Runs dictation as one continuous take. With an online recognizer that
/// means restarting it whenever Android ends a session on a pause, and
/// giving up after a stretch of silence so the mic isn't left on.
class DictationController extends ChangeNotifier {
  DictationController(
    this._engine, {
    this.restartDelay = const Duration(milliseconds: 250),
    this.maxSilentSessions = 4,
    this.maxFailedSessions = 3,
  });

  final SpeechEngine _engine;
  final Duration restartDelay;

  /// Sessions in a row with no words before dictation stops by itself.
  final int maxSilentSessions;

  /// Sessions in a row that failed with an error before giving up. Online
  /// recognizers often drop the connection when the speaker pauses, so one
  /// failure alone is no reason to stop.
  final int maxFailedSessions;

  /// Errors that just mean "nothing was said".
  static const _silenceErrors = {'error_no_match', 'error_speech_timeout'};

  /// Errors no restart can fix.
  static const _fatalErrors = {
    'error_permission',
    'error_audio_error',
    'error_language_not_supported',
    'error_language_unavailable',
  };

  /// Languages already offered for download this run, so it's asked once.
  static final _offeredDownloads = <String>{};

  final _transcript = DictationTranscript();
  bool _wanted = false;
  bool _stopping = false;
  bool _sessionOpen = false;
  bool _sessionHeard = false;
  String? _lastFinal;
  int _silentSessions = 0;
  int _failedSessions = 0;
  Timer? _restartTimer;
  String _localeId = defaultDictationLocale;

  /// Called with a user-facing message when dictation can't continue.
  void Function(String message)? onProblem;

  /// Called once per language when its offline model could be downloaded
  /// for continuous, offline dictation.
  void Function(String localeId)? onOfferDownload;

  bool get isListening => _wanted;

  /// What this take has heard. Each [start] begins a new, empty take.
  String get text => _transcript.text;

  String get localeId => _localeId;

  Future<void> start({required String localeId}) async {
    if (_wanted) return;
    _localeId = localeId;
    _transcript.clear();
    _attach();
    if (!await _prepare()) return;
    _wanted = true;
    _silentSessions = 0;
    _failedSessions = 0;
    notifyListeners();
    await _engine.setQuiet(true);
    await _listen();
  }

  /// Switches language mid-dictation; what was heard so far is kept.
  Future<void> switchLocale(String localeId) async {
    _localeId = localeId;
    if (!_wanted) return;
    _restartTimer?.cancel();
    _sessionOpen = false;
    _transcript.commit();
    await _engine.stop();
    if (!await _prepare()) {
      await stop();
      return;
    }
    await _listen();
  }

  Future<void> stop() async {
    if (!_wanted || _stopping) return;
    _stopping = true;
    _restartTimer?.cancel();
    notifyListeners();
    // Words still on their way arrive here.
    await _engine.stop();
    _stopping = false;
    _wanted = false;
    _sessionOpen = false;
    _transcript.commit();
    notifyListeners();
    await _engine.setQuiet(false);
  }

  Future<void> downloadLanguage(String localeId) async {
    if (!await _engine.downloadLanguage(localeId)) {
      onProblem?.call("This phone can't download offline speech models.");
    }
  }

  Future<String> describe() => _engine.describe();

  Future<bool> _prepare() async {
    final setup = await _engine.prepare(_localeId);
    if (!setup.available) {
      onProblem?.call(_setupMessage(setup.problem));
      return false;
    }
    if (setup.canDownload && _offeredDownloads.add(_localeId)) {
      onOfferDownload?.call(_localeId);
    }
    return true;
  }

  void _attach() {
    _engine
      ..onWords = _onWords
      ..onSessionEnd = _onSessionEnd
      ..onError = _onError;
  }

  Future<void> _listen() async {
    _sessionOpen = true;
    _sessionHeard = false;
    _lastFinal = null;
    try {
      await _engine.listen(localeId: _localeId);
    } on PlatformException {
      _fail("Couldn't start listening. Try again.");
    }
  }

  void _onWords(String words, bool isFinal) {
    if (!_wanted) return;
    final heard = words.trim();
    // Some recognizers repeat a final result; the first one wins.
    if (isFinal && heard == _lastFinal) return;
    _transcript.update(heard);
    if (heard.isNotEmpty) {
      _sessionHeard = true;
      _failedSessions = 0;
    }
    if (isFinal) {
      _transcript.commit();
      _lastFinal = heard;
    } else {
      _lastFinal = null;
    }
    notifyListeners();
  }

  void _onSessionEnd(bool idle, {bool failed = false}) {
    if (!_sessionOpen) return;
    _sessionOpen = false;
    _transcript.commit();
    if (!_wanted || _stopping) return;
    if (idle) {
      stop();
      return;
    }

    _silentSessions = _sessionHeard ? 0 : _silentSessions + 1;
    if (_silentSessions >= maxSilentSessions) {
      stop();
      return;
    }
    // Back off a little after failures so a flaky connection can recover.
    final delay = failed ? restartDelay * (2 * _failedSessions) : restartDelay;
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (_wanted) _listen();
    });
  }

  void _onError(String code) {
    if (!_wanted || !_sessionOpen) return;
    if (_fatalErrors.contains(code)) {
      // While stopping this is the last phrase failing: say so, since its
      // words are lost.
      if (_stopping) {
        onProblem?.call(_messageFor(code));
      } else {
        _fail(_messageFor(code));
      }
      return;
    }
    if (_stopping) return;
    // Once this take has heard anything the connection is known to work,
    // and Google's recognizer reports a long pause as a dropped connection
    // ("server disconnected", "network"). So it counts as silence: dictation
    // then stops quietly after the silence limit instead of blaming the
    // internet.
    final silence = _silenceErrors.contains(code) || !_transcript.isEmpty;
    if (!silence) {
      _failedSessions++;
      if (_failedSessions >= maxFailedSessions) {
        _fail(_messageFor(code));
        return;
      }
    }
    // The session may already be over without an end to follow.
    _onSessionEnd(false, failed: !silence);
  }

  void _fail(String message) {
    stop();
    onProblem?.call(message);
  }

  static String _setupMessage(String? problem) {
    switch (problem) {
      case 'permission':
        return 'Habit Loop needs the microphone for dictation. '
            'Allow it in App info → Permissions.';
      case 'needs_download':
        return 'Download the offline speech model for this language first.';
      default:
        return "Speech recognition isn't available on this phone.";
    }
  }

  static String _messageFor(String code) {
    switch (code) {
      case 'error_permission':
        return 'Microphone permission is off for Habit Loop.';
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return "This phone's speech service can't do this language. "
            'Make sure the Google app is installed and up to date.';
      case 'error_audio_error':
        return "Couldn't use the microphone. Is another app recording?";
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
      case 'error_server_disconnected':
        return 'Speech needs internet for this language unless its '
            'offline model is downloaded.';
      default:
        return 'Dictation stopped ($code).';
    }
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    if (_wanted) {
      _engine
        ..cancel()
        ..setQuiet(false);
    }
    _wanted = false;
    _engine
      ..onWords = null
      ..onSessionEnd = null
      ..onError = null;
    super.dispose();
  }
}

/// [base] with [text] inserted at its cursor (replacing any selection),
/// spaced from the surrounding words, and capitalised at the start of a
/// sentence. The cursor ends up after the inserted text.
TextEditingValue insertDictation(TextEditingValue base, String text) {
  final words = text.trim();
  if (words.isEmpty) return base;

  final value = base.text;
  final selection = base.selection;
  final start = selection.isValid ? selection.start : value.length;
  final end = selection.isValid ? selection.end : value.length;
  final before = value.substring(0, start);
  final after = value.substring(end);

  final sentenceStart = before.trim().isEmpty ||
      RegExp(r'[.!?।\n]\s*$').hasMatch(before);
  final inserted =
      sentenceStart ? words[0].toUpperCase() + words.substring(1) : words;
  final lead = before.isEmpty || RegExp(r'\s$').hasMatch(before) ? '' : ' ';
  final trail = after.isEmpty || RegExp(r'^\s').hasMatch(after) ? '' : ' ';

  final newBefore = '$before$lead$inserted';
  return TextEditingValue(
    text: '$newBefore$trail$after',
    selection: TextSelection.collapsed(offset: newBefore.length),
  );
}

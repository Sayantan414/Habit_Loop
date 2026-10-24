import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'gemini_transcriber.dart';
import 'speech_service.dart';

/// Gemini dictation, like a voice message: MemoRecorder.kt records the whole
/// take, and when the user stops it's transcribed in one go.
///
/// Nothing appears while speaking, but the full recording gives Gemini all
/// the context, which is what makes Bengali and long sentences come out
/// right, and a whole note costs a single request.
class GeminiSpeechEngine extends SpeechEngine {
  GeminiSpeechEngine(this._transcriber, {SpeechBridge? bridge})
      : _bridge = bridge ?? SpeechBridge.instance;

  final GeminiTranscriber _transcriber;
  final SpeechBridge _bridge;

  /// Retries for rate limits and network blips; the recording is kept
  /// until they're used up.
  static const _maxRetries = 2;
  static const _maxRetryWait = Duration(seconds: 10);

  List<String> _languages = const [];
  String? _lastError;

  /// The last recording if transcribing it failed, kept in memory so the
  /// note isn't lost to a dropped connection.
  Uint8List? _failedAudio;

  MethodChannel get _channel => _bridge.channel;

  Future<void> _onCall(MethodCall call) async {
    // The 20-minute limit was reached: finish as if the user stopped.
    if (call.method == 'onMemoLimit') onSessionEnd?.call(true);
  }

  @override
  Future<SpeechSetup> prepare(String localeId) async {
    _bridge.claim(_onCall);
    try {
      final granted =
          await _channel.invokeMethod<bool>('ensureMicPermission') ?? false;
      if (!granted) {
        return const SpeechSetup(available: false, problem: 'permission');
      }
      return const SpeechSetup(available: true, continuous: true);
    } on PlatformException {
      return const SpeechSetup(available: false, problem: 'unavailable');
    } on MissingPluginException {
      // Not on Android.
      return const SpeechSetup(available: false, problem: 'unavailable');
    }
  }

  @override
  Future<void> listen({required String localeId}) async {
    // Bengali speech is usually mixed with English, so allow both.
    _languages = localeId.startsWith('bn') ? [localeId, 'en-IN'] : [localeId];
    final status = await _channel.invokeMethod<String>('startMemo');
    if (status != 'ok') _report(status ?? 'error_audio_error');
  }

  @override
  Future<void> stop() async {
    final String? path;
    try {
      path = await _channel.invokeMethod<String>('stopMemo', {'keep': true});
    } on PlatformException {
      return;
    }
    if (path == null) return;
    final file = File(path);
    try {
      final audio = await file.readAsBytes();
      // Kept before trying, so it can already be retried when the error is
      // reported.
      _failedAudio = audio;
      final text = await _transcribe(audio);
      if (text != null) {
        _failedAudio = null;
        if (text.isNotEmpty) onWords?.call(text, true);
      }
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  bool get canRetry => _failedAudio != null;

  @override
  Future<String?> retryFailed() async {
    final audio = _failedAudio;
    if (audio == null) return null;
    final text = await _transcribe(audio);
    if (text != null) _failedAudio = null;
    return text;
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<String>('stopMemo', {'keep': false});
    } on PlatformException {
      // Not recording.
    }
  }

  @override
  Future<bool> downloadLanguage(String localeId) async => false;

  /// Nothing beeps: the app records the mic itself.
  @override
  Future<void> setQuiet(bool quiet) async {}

  @override
  Future<String> describe() async =>
      'Gemini · ${GeminiTranscriber.model} · languages: ${_languages.join(', ')}'
      '${_lastError == null ? '' : ' · last error: $_lastError'}';

  Future<String?> _transcribe(Uint8List audio) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _transcriber.transcribe(audio, languages: _languages);
      } on TranscriptionException catch (e) {
        if (e.code == 'gemini_auth' || attempt >= _maxRetries) {
          _report(e.code);
          return null;
        }
        final wait = e.retryAfter ?? Duration(seconds: attempt + 1);
        await Future<void>.delayed(wait > _maxRetryWait ? _maxRetryWait : wait);
      }
    }
  }

  void _report(String code) {
    _lastError = code;
    onError?.call(code);
  }
}

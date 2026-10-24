import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Why a transcription failed. [code] is one of `gemini_auth`,
/// `gemini_quota`, `gemini_network` or `gemini_server`.
class TranscriptionException implements Exception {
  const TranscriptionException(this.code, {this.retryAfter});

  final String code;

  /// How long Google asked us to wait (rate limits only).
  final Duration? retryAfter;

  @override
  String toString() => 'TranscriptionException($code)';
}

/// Speech to text with Gemini's dedicated transcription model, on the free
/// tier, using the user's own key.
///
/// One recording is one transcription: the audio is uploaded with the Files
/// API, transcribed, and deleted straight away rather than left for Google's
/// 48-hour clean-up.
class GeminiTranscriber {
  GeminiTranscriber({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  static const model = 'gemini-3.5-transcribe';

  static const _host = 'https://generativelanguage.googleapis.com';
  static final _upload = Uri.parse('$_host/upload/v1beta/files');
  static final _interactions = Uri.parse('$_host/v1beta/interactions');
  static final _models = Uri.parse('$_host/v1beta/models');

  static const _timeout = Duration(seconds: 60);
  static const _pollEvery = Duration(seconds: 1);
  static const _maxPolls = 90;

  final String apiKey;
  final http.Client _client;

  Map<String, String> get _auth => {'x-goog-api-key': apiKey};

  /// Text spoken in [audio]. [languages] are BCP-47 codes such as `bn-IN`;
  /// empty lets Gemini detect the language itself.
  Future<String> transcribe(
    Uint8List audio, {
    String mimeType = 'audio/m4a',
    List<String> languages = const [],
  }) async {
    final file = await _uploadFile(audio, mimeType);
    try {
      var interaction = _json(
        await _send(
          http.Request('POST', _interactions)
            ..headers.addAll({..._auth, 'Content-Type': 'application/json'})
            ..body = jsonEncode({
              'model': model,
              'input': [
                {'type': 'audio', 'uri': file.uri, 'mime_type': mimeType},
              ],
              if (languages.isNotEmpty)
                'generation_config': {
                  'transcription_config': {'language_codes': languages},
                },
            }),
        ),
      );
      // Long recordings may still be running when the call returns.
      for (var i = 0; _isRunning(interaction) && i < _maxPolls; i++) {
        await Future<void>.delayed(_pollEvery);
        interaction = _json(
          await _send(
            http.Request('GET', Uri.parse('$_host/v1beta/${interaction['id']}'))
              ..headers.addAll(_auth),
          ),
        );
      }
      if (_isRunning(interaction)) {
        throw const TranscriptionException('gemini_server');
      }
      return transcriptOf(interaction);
    } finally {
      unawaited(_deleteFile(file.name));
    }
  }

  /// True if Google accepts the key; throws [TranscriptionException] when
  /// it can't tell (no internet, Google down).
  Future<bool> checkKey() async {
    try {
      await _send(http.Request('GET', _models)..headers.addAll(_auth));
      return true;
    } on TranscriptionException catch (e) {
      if (e.code == 'gemini_auth') return false;
      rethrow;
    }
  }

  void close() => _client.close();

  /// The transcript in an interaction: `output_text` where present, else the
  /// text parts of its model output steps.
  static String transcriptOf(Map<String, dynamic> interaction) {
    final direct = interaction['output_text'];
    if (direct is String) return direct.trim();
    final parts = <String>[];
    for (final step in interaction['steps'] as List? ?? const []) {
      if (step is! Map || step['type'] != 'model_output') continue;
      for (final part in step['content'] as List? ?? const []) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          parts.add(part['text'] as String);
        }
      }
    }
    return parts.join(' ').trim();
  }

  static bool _isRunning(Map<String, dynamic> interaction) {
    final status = interaction['status'];
    return status == 'in_progress' || status == 'pending';
  }

  Future<({String uri, String name})> _uploadFile(
    Uint8List audio,
    String mimeType,
  ) async {
    final start = await _send(
      http.Request('POST', _upload)
        ..headers.addAll({
          ..._auth,
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': '${audio.length}',
          'X-Goog-Upload-Header-Content-Type': mimeType,
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({
          'file': {'display_name': 'habit-loop-dictation'},
        }),
    );
    final uploadUrl = start.headers['x-goog-upload-url'];
    if (uploadUrl == null) throw const TranscriptionException('gemini_server');

    final done = _json(
      await _send(
        http.Request('POST', Uri.parse(uploadUrl))
          ..headers.addAll({
            'X-Goog-Upload-Offset': '0',
            'X-Goog-Upload-Command': 'upload, finalize',
          })
          ..bodyBytes = audio,
      ),
    );
    final file = done['file'] as Map<String, dynamic>?;
    final uri = file?['uri'] as String?;
    final name = file?['name'] as String?;
    if (uri == null || name == null) {
      throw const TranscriptionException('gemini_server');
    }
    return (uri: uri, name: name);
  }

  Future<void> _deleteFile(String name) async {
    try {
      await _client
          .delete(Uri.parse('$_host/v1beta/$name'), headers: _auth)
          .timeout(_timeout);
    } on Exception {
      // Google deletes it after 48 hours anyway.
    }
  }

  /// Sends [request]; any non-2xx answer becomes a [TranscriptionException].
  Future<http.Response> _send(http.BaseRequest request) async {
    final http.Response response;
    try {
      response =
          await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } on TimeoutException {
      throw const TranscriptionException('gemini_network');
    } on http.ClientException {
      throw const TranscriptionException('gemini_network');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _failure(response);
  }

  // Decoded by hand: without a charset in the response, `body` would be
  // read as Latin-1 and garble Bengali.
  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

  static TranscriptionException _failure(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    switch (response.statusCode) {
      case 401:
      case 403:
        return const TranscriptionException('gemini_auth');
      case 400 when body.contains('API_KEY_INVALID'):
        return const TranscriptionException('gemini_auth');
      case 429:
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        return TranscriptionException(
          'gemini_quota',
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      default:
        return const TranscriptionException('gemini_server');
    }
  }
}

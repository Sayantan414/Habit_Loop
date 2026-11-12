import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Why a Gemini request failed. [code] is one of `gemini_auth`,
/// `gemini_quota`, `gemini_network` or `gemini_server`.
class GeminiException implements Exception {
  const GeminiException(this.code, {this.retryAfter, this.detail});

  final String code;

  /// Google's own words for an unexpected failure (`gemini_server`), or
  /// what went wrong on the way (`gemini_network`), so the message says
  /// more than "a problem".
  final String? detail;

  /// How long Google asked us to wait (rate limits only).
  final Duration? retryAfter;

  @override
  String toString() => 'GeminiException($code)';
}

/// One function call the model asked for: a tool [name] and its arguments.
class GeminiCall {
  const GeminiCall(this.name, this.args);

  final String name;
  final Map<String, dynamic> args;
}

/// What the model answered: any text, plus the tools it wants run.
class GeminiReply {
  const GeminiReply({this.text = '', this.calls = const [], this.model});

  final String text;
  final List<GeminiCall> calls;

  /// Which of [GeminiClient.chatModels] answered.
  final String? model;
}

/// The Gemini API on the free tier, with the user's own key.
class GeminiClient {
  GeminiClient({
    required this.apiKey,
    http.Client? client,
    this.chatTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  static const host = 'https://generativelanguage.googleapis.com';
  static final _models = Uri.parse('$host/v1beta/models');
  static final _interactions = Uri.parse('$host/v1beta/interactions');

  /// Free-tier models, fastest first: Flash-Lite is quick and plenty for
  /// to-dos and notes. The next one is tried when a model is gone (404),
  /// its own daily limit is used up (429), or it's overloaded (503) or too
  /// slow: on the free tier Google turns requests away when demand spikes,
  /// and each model has its own capacity.
  static const chatModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
  ];

  static const _timeout = Duration(seconds: 60);

  static const _fallbackCodes = {
    'gemini_quota',
    'gemini_missing',
    'gemini_busy',
    'gemini_timeout',
  };

  final String apiKey;
  final http.Client _client;

  /// Per model in [interact]; a normal answer takes a few seconds, so a
  /// model this slow is better skipped than waited for.
  final Duration chatTimeout;

  Map<String, String> get _auth => {'x-goog-api-key': apiKey};

  /// True if Google accepts the key; throws [GeminiException] when it
  /// can't tell (no internet, Google down).
  Future<bool> checkKey() async {
    try {
      await _send(http.Request('GET', _models)..headers.addAll(_auth));
      return true;
    } on GeminiException catch (e) {
      if (e.code == 'gemini_auth') return false;
      rethrow;
    }
  }

  /// One stateless turn with function calling: nothing is stored at
  /// Google, so [input] carries whatever context the turn needs.
  Future<GeminiReply> interact({
    required String systemInstruction,
    required String input,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    // Light thinking keeps answers quick; dropped if a model rejects it.
    var thinking = true;
    for (var i = 0; i < chatModels.length;) {
      try {
        final response = await _send(
          http.Request('POST', _interactions)
            ..headers.addAll({..._auth, 'Content-Type': 'application/json'})
            ..body = jsonEncode({
              'model': chatModels[i],
              'system_instruction': systemInstruction,
              'input': input,
              if (tools.isNotEmpty) 'tools': tools,
              'generation_config': {
                if (thinking) 'thinking_level': 'low',
                if (tools.isNotEmpty) 'tool_choice': 'auto',
              },
              'store': false,
            }),
          timeout: chatTimeout,
        );
        final reply = replyOf(_json(response));
        return GeminiReply(
          text: reply.text,
          calls: reply.calls,
          model: chatModels[i],
        );
      } on GeminiException catch (e) {
        if (thinking &&
            e.code == 'gemini_server' &&
            (e.detail ?? '').contains('thinking')) {
          thinking = false;
          continue;
        }
        if (!_fallbackCodes.contains(e.code) || i == chatModels.length - 1) {
          throw switch (e.code) {
            'gemini_missing' => const GeminiException('gemini_server'),
            'gemini_timeout' => GeminiException(
              'gemini_busy',
              detail: e.detail,
            ),
            _ => e,
          };
        }
        i++;
      }
    }
    throw const GeminiException('gemini_server');
  }

  void close() => _client.close();

  /// The text and function calls in an interaction's steps.
  static GeminiReply replyOf(Map<String, dynamic> interaction) {
    final texts = <String>[];
    final calls = <GeminiCall>[];
    for (final step in interaction['steps'] as List? ?? const []) {
      if (step is! Map) continue;
      switch (step['type']) {
        case 'function_call':
          final name = step['name'];
          final args = step['arguments'];
          if (name is String) {
            calls.add(
              GeminiCall(
                name,
                args is Map ? Map<String, dynamic>.from(args) : const {},
              ),
            );
          }
        case 'model_output':
          for (final part in step['content'] as List? ?? const []) {
            if (part is Map &&
                part['type'] == 'text' &&
                part['text'] is String) {
              texts.add(part['text'] as String);
            }
          }
      }
    }
    final direct = interaction['output_text'];
    if (texts.isEmpty && direct is String) texts.add(direct);
    return GeminiReply(text: texts.join('\n').trim(), calls: calls);
  }

  /// Sends [request]; any non-2xx answer becomes a [GeminiException].
  Future<http.Response> _send(
    http.BaseRequest request, {
    Duration timeout = _timeout,
  }) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException {
      // The connection worked (or we'd have a ClientException); Google just
      // didn't answer in time.
      throw GeminiException(
        'gemini_timeout',
        detail: 'no answer in ${timeout.inSeconds} s',
      );
    } on http.ClientException catch (e) {
      throw GeminiException('gemini_network', detail: e.message);
    } on IOException catch (e) {
      // TLS failures (e.g. a VPN or DNS blocker in the way) aren't wrapped
      // in a ClientException.
      throw GeminiException('gemini_network', detail: '$e');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw failureFor(response);
  }

  // Decoded by hand: without a charset in the response, `body` would be
  // read as Latin-1 and garble Bengali.
  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

  /// Maps an error response to a [GeminiException]. `gemini_missing` (an
  /// unknown model) never leaves this class.
  static GeminiException failureFor(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    switch (response.statusCode) {
      case 401:
      case 403:
        return const GeminiException('gemini_auth');
      case 400 when body.contains('API_KEY_INVALID'):
        return const GeminiException('gemini_auth');
      case 404:
        return const GeminiException('gemini_missing');
      case 429:
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        return GeminiException(
          'gemini_quota',
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      case 500 || 502 || 503 || 504:
        return GeminiException('gemini_busy', detail: _message(body, response));
      default:
        return GeminiException(
          'gemini_server',
          detail: _message(body, response),
        );
    }
  }

  /// The status code plus Google's own explanation, when it gives one.
  static String _message(String body, http.Response response) {
    final message = RegExp(r'"message"\s*:\s*"([^"]*)"').firstMatch(body)?[1];
    return '${response.statusCode}${message == null ? '' : ': $message'}';
  }
}
